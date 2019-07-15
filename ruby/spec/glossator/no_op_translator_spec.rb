require 'rails_helper'

RSpec.describe Glossator::NoOpTranslator do
  it "returns the given data object unchanged" do
    translator = Glossator::NoOpTranslator.new("1.2.3")
    data = { foo: "bar" }
    expect(translator.translate(:request_up, data)).to eq(foo: "bar").and equal(data)
    expect(translator.translate(:response_down, data)).to eq(foo: "bar").and equal(data)
  end
end
