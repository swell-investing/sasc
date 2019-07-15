require 'rails_helper'

RSpec.describe Glossator::Translator do
  it "defaults to changing nothing during translation" do
    translator_class = define_translator_class("PersonResourceTranslator")
    translator = translator_class.new("0.9.9")

    expect(translator.translate(:request_up, foo: "bar")).to eq(foo: "bar")
    expect(translator.translate(:response_down, foo: "bar")).to eq(foo: "bar")
  end

  it "returns translated data as a duped object" do
    translator_class = define_translator_class("PersonResourceTranslator") do
      def request_up(data)
        data.deep_merge!(baz: "narf")
      end

      def response_down(data)
        data.delete(:baz)
      end
    end
    translator = translator_class.new("0.9.9")

    data = { foo: "bar" }
    translated = translator.translate(:request_up, data)
    expect(data).to eq(foo: "bar")
    expect(translated).to eq(foo: "bar", baz: "narf")

    expect(translator.translate(:response_down, translated)).to eq(foo: "bar")
    expect(translated).to eq(foo: "bar", baz: "narf")
  end

  it "can specify that the target version is unsupported" do
    translator_class = define_translator_class("PersonResourceTranslator") do
      def version_not_supported?
        version_below? "1.0.0"
      end

      def request_up(data)
        data.deep_merge!(baz: "narf") if version_below? "1.0.1"
      end
    end

    expect { translator_class.new("0.9.9") }.to raise_error(
      Glossator::Errors::UnsupportedVersionError, "Version 0.9.9 is not supported"
    )

    translator = translator_class.new("1.0.0")
    expect(translator.translate(:request_up, {})).to eq(baz: "narf")
  end

  it "complains if given an unknown translation mode" do
    translator_class = define_translator_class("PersonResourceTranslator")
    translator = translator_class.new("0.9.9")

    expect { translator.translate(:narf, foo: "bar") }.to raise_error(
      ArgumentError, "Unknown translation mode :narf"
    )
  end

  it "complains if data is not a hash" do
    translator_class = define_translator_class("PersonResourceTranslator")
    translator = translator_class.new("0.9.9")

    expect { translator.translate(:request_up, [{ foo: "bar" }]) }.to raise_error(
      ArgumentError, "data must be Hash"
    )
    expect { translator.translate(:request_up, 123) }.to raise_error(
      ArgumentError, "data must be Hash"
    )
    expect { translator.translate(:response_down, [{ foo: "bar" }]) }.to raise_error(
      ArgumentError, "data must be Hash"
    )
    expect { translator.translate(:response_down, 123) }.to raise_error(
      ArgumentError, "data must be Hash"
    )
  end

  it "complains if translator tries to use string keys" do
    translator_class = define_translator_class("PersonResourceTranslator") do
      def response_down(data)
        data.deep_merge!(foo: { "bar" => 123 })
      end
    end
    translator = translator_class.new("0.9.9")

    expect { translator.translate(:response_down, {}) }.to raise_error(
      Glossator::Errors::BadKeyConversionError, "Non-symbol key \"bar\" (in: [:foo])"
    )
  end

  it "does not complain if string key was already present in original data" do
    translator_class = define_translator_class("PersonResourceTranslator") do
      def response_down(data)
        data.deep_merge!(foo: { bar: 123 })
      end
    end
    translator = translator_class.new("0.9.9")

    expect(translator.translate(:response_down, foo: { "wat" => 789 })).to eq(
      foo: { bar: 123, "wat" => 789 }
    )
  end

  it "complains if translator tries to use snake_case keys" do
    translator_class = define_translator_class("PersonResourceTranslator") do
      def response_down(data)
        data.deep_merge!(foo: { bar_baz: 123 })
      end
    end
    translator = translator_class.new("0.9.9")

    expect { translator.translate(:response_down, {}) }.to raise_error(
      Glossator::Errors::BadKeyConversionError, "Non-camelCase key :bar_baz (in: [:foo])"
    )
  end

  it "does not complain if snake case key was already present in original data" do
    translator_class = define_translator_class("PersonResourceTranslator") do
      def response_down(data)
        data.deep_merge!(foo: { bar: 123 })
      end
    end
    translator = translator_class.new("0.9.9")

    expect(translator.translate(:response_down, foo: { narf_bork: 789 })).to eq(
      foo: { narf_bork: 789, bar: 123 }
    )
  end

  def define_translator_class(class_name, &block)
    define_anonymous_class(Glossator::Translator, class_name, &block)
  end
end
