module SASC
  module VersionChangelog
    class << self
      def build
        version_openapis = SASC::Versioning.versions.keys.sort.map do |ver|
          SASC::Versioning.expand_openapi(SASC::Versioning.get_openapi(ver))
        end

        [
          changelog_entry(nil, version_openapis.first, []),
        ] + version_openapis.each_cons(2).map do |a, b|
          changes = SASC::Versioning::Diff.new(a, b).interesting_changes
          changelog_entry(a, b, changes)
        end
      end

      private

      def changelog_entry(a, b, changes)
        {
          old: a ? info_without_markdown_prefix(a["info"]) : nil,
          new: info_without_markdown_prefix(b["info"]),
          change_groups: group_changes_by_shared_prefixes(changes),
        }
      end

      def info_without_markdown_prefix(openapi_info)
        openapi_info.merge("description" => openapi_info["description"].sub(/^\*\*Version \S+:\*\* /, ''))
      end

      def group_changes_by_shared_prefixes(changes)
        max_prefix_length = changes.map { |c| c[:path].length - 1 }.max
        groups_hash = find_common_prefixes(changes, max_prefix_length)
        convert_change_paths_to_suffixes!(groups_hash)
        clean_up_ungrouped_changes!(groups_hash)
        merge_by_same_contents(groups_hash)
      end

      # rubocop:disable Metrics/MethodLength
      def find_common_prefixes(changes, prefix_length)
        return {} if changes.empty?
        return { ungrouped: changes } if prefix_length <= 1

        unmatched = []
        groups = {}
        changes.each do |change|
          if change[:path].length > prefix_length
            prefix = change[:path].take(prefix_length)
            groups[prefix] ||= []
            groups[prefix].push(change)
          else
            unmatched.push(change)
          end
        end

        groups.keys.each do |prefix|
          unmatched.concat(groups.delete(prefix)) if groups[prefix].length == 1
        end

        groups.merge(find_common_prefixes(unmatched, prefix_length - 1))
      end
      # rubocop:enable Metrics/MethodLength

      def clean_up_ungrouped_changes!(groups_hash)
        return unless groups_hash.key?(:ungrouped)

        groups_hash.delete(:ungrouped).each do |c|
          prefix = c[:suffix].take(c[:suffix].length - 1)
          chomped_changes = [c.merge(suffix: [c[:suffix].last])]
          groups_hash[prefix] ||= []
          groups_hash[prefix].concat chomped_changes
        end
      end

      def convert_change_paths_to_suffixes!(groups_hash)
        groups_hash.each do |prefix, group_changes|
          group_changes.each do |c|
            c[:suffix] = c.delete(:path).drop(prefix == :ungrouped ? 0 : prefix.length)
          end
        end
      end

      def merge_by_same_contents(groups_hash)
        inverted_groups = {}

        groups_hash.each do |prefix, changes|
          key = changes.hash
          inverted_groups[key] ||= { prefixes: [], changes: changes }
          inverted_groups[key][:prefixes].push(prefix)
          inverted_groups[key][:prefixes].sort!
        end

        inverted_groups.values.sort_by { |group| group[:prefixes].first }
      end
    end
  end
end
