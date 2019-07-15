module SASC
  #.## SASC::Versioning
  #. Information about application API versions
  module Versioning
    #% SASC::Versioning.versions
    #. Returns a hash describing all available API versions, with Semantic::Version keys
    def self.versions
      @versions ||= Rails.configuration.sasc_api_versions.transform_keys(&:to_version)
    end

    #% SASC::Versioning.latest_version
    #. Returns the most recent version as a Semantic::Version
    def self.latest_version
      @latest_version ||= versions.keys.sort.last
    end

    #% SASC::Versioning.create_translator
    #. Instantiates an appropriate Glossator::Translator
    #.
    #. If the given translator class is nil, or if the given target version is equal to the latest
    #. version, then an instance of Glossator::NoOpTranslator is returned. Otherwise, the given
    #. translator class is instantiated with the given target version.
    #.
    #. * `translator_class`: A class deriving from Glossator::Translator, or nil
    #. * `target_version`: A Semantic::Version or string with the client's requested API version
    def self.create_translator(translator_class, target_version)
      target_version = Semantic::Version.new(target_version) unless target_version.is_a?(Semantic::Version)

      if translator_class.nil? || target_version == latest_version
        return Glossator::NoOpTranslator.new(target_version)
      end

      if target_version > latest_version
        raise ArgumentError, "target_version must not be greater than the latest_version"
      end

      unless translator_class.try(:superclass) == Glossator::Translator
        raise ArgumentError, "translator class must be a class derived from Glossator::Translator"
      end

      translator_class.new(target_version)
    end

    def self.get_openapi(version)
      version = Semantic::Version.new(version) unless version.is_a?(Semantic::Version)

      path = File.join("openapi", "v#{version}.json.gz")
      raise ArgumentError, "no openapi for version #{version}" unless File.exist?(path)
      gzipped_body = File.binread(path)
      JSON.load(ActiveSupport::Gzip.decompress(gzipped_body))
    end

    def self.expand_openapi(openapi)
      expand_json_refs(openapi).except("components")
    end

    def self.expand_json_refs(root, current = nil)
      current = root if current.nil?

      case current
      when Array
        current.map { |elem| expand_json_refs(root, elem) }
      when Hash
        if current.key?("$ref")
          raise "Cannot mix $ref with other keys" unless current.keys.length == 1
          expand_json_refs(root, evaluate_json_ref(root, current["$ref"]))
        else
          current.transform_values { |value| expand_json_refs(root, value) }
        end
      else
        current
      end
    end
    private_class_method :expand_json_refs

    def self.evaluate_json_ref(root, ref_path)
      raise "Invalid $ref path, must start with #" unless ref_path.start_with?("#")
      ref_path = URI.decode_www_form_component(ref_path.sub(/^#/, ''))
      Hana::Pointer.new(ref_path).eval(root)
    end
    private_class_method :evaluate_json_ref

    class Diff
      attr_reader :changes

      def initialize(a, b, expand: true)
        if Semantic::Version.new(a["info"]["version"]) > Semantic::Version.new(b["info"]["version"])
          raise ArgumentError, "Cannot diff from newer version to older version"
        end

        if expand
          a = SASC::Versioning.expand_openapi(a)
          b = SASC::Versioning.expand_openapi(b)
        end

        @changes = HashDiff.diff(a, b, delimiter: " -> ").map do |diff_row|
          {
            path: diff_row[1].split(" -> "),
            op: diff_row[0],
            content: diff_row.drop(2),
          }
        end
      end

      delegate :empty?, to: :changes

      def trivial?
        @changes.all? do |c|
          %w(description summary).include?(c[:path].last) || c[:path].include?("example")
        end
      end

      def interesting_changes
        @changes.select do |c|
          next false if boring_path?(c[:path])

          if c[:content].length == 1
            h = c[:content][0]
            next false if h.is_a?(Hash) && h["in"] == "header" && h["name"] == "x-sasc-api-version"
          end

          true
        end
      end

      def to_s
        lines = @changes.map do |change|
          [
            "",
            change[:path].join(" -> "),
            "#{change[:op]} #{change[:content].join(' => ')}",
          ]
        end

        lines.flatten.join("\n") + "\n"
      end

      private

      def boring_path?(path)
        path == %w(info description) ||
          path == %w(info version) ||
          (path.include?("headers") && path.include?("x-sasc-api-version"))
      end
    end
  end
end
