RSpec.describe SASC::Validation do
  it "validates strings" do
    expect(SASC::Validation.valid?(:string, "foo")).to eq(true)
    expect(SASC::Validation.valid?(:string, 3)).to eq(false)
  end

  it "validates integers" do
    expect(SASC::Validation.valid?(:integer, "foo")).to eq(false)
    expect(SASC::Validation.valid?(:integer, 3)).to eq(true)
  end

  it "validates booleans" do
    expect(SASC::Validation.valid?(:boolean, true)).to eq(true)
    expect(SASC::Validation.valid?(:boolean, false)).to eq(true)
    expect(SASC::Validation.valid?(:boolean, 3)).to eq(false)
  end

  it "validates against JSON Schema documents" do
    schema = {
      type: :object,
      properties: {
        abc: {
          type: :integer,
          minimum: 11,
        },
      },
    }

    # Should be agnostic on whether keys are symbols or strings
    expect(SASC::Validation.valid?(schema, abc: 13)).to eq(true)
    expect(SASC::Validation.valid?(schema, "abc" => 13)).to eq(true)

    expect(SASC::Validation.valid?(schema, abc: 10)).to eq(false)
    expect(SASC::Validation.valid?(schema, "abc" => 10)).to eq(false)
    expect(SASC::Validation.valid?(schema, 37)).to eq(false)
    expect(SASC::Validation.valid?(schema, "foo")).to eq(false)
  end

  it "forbids additional properties in objects by default" do
    schema = {
      type: :object,
      properties: {
        abc: { type: :integer },
      },
    }

    expect(SASC::Validation.valid?(schema, abc: 13)).to eq(true)
    expect(SASC::Validation.valid?(schema, abc: 13, xyz: "wat")).to eq(false)
  end

  it "permits additional properties in objects if explicitly requested" do
    schema = {
      type: :object,
      properties: {
        abc: { type: :integer },
      },
      additionalProperties: true,
    }

    expect(SASC::Validation.valid?(schema, abc: 13)).to eq(true)
    expect(SASC::Validation.valid?(schema, abc: 13, xyz: "wat")).to eq(true)
  end

  it "forbids additional items in tuple-like arrays by default" do
    schema = {
      type: :array,
      items: [
        { type: :integer },
      ],
    }

    expect(SASC::Validation.valid?(schema, [13])).to eq(true)
    expect(SASC::Validation.valid?(schema, [13, 14])).to eq(false)
  end

  it "permits additional items in tuple-like arrays if explicitly requested" do
    schema = {
      type: :array,
      items: [
        { type: :integer },
      ],
      additionalItems: true,
    }

    expect(SASC::Validation.valid?(schema, [13])).to eq(true)
    expect(SASC::Validation.valid?(schema, [13, 14])).to eq(true)
  end

  it "raises ArgumentError if given value that has no JSON representation" do
    expect {
      SASC::Validation.valid?(:boolean, Kernel)
    }.to raise_error(ArgumentError, "Non-JSONable value Kernel")
  end
end
