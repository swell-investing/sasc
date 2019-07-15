module Glossator
  module Errors
    class BadKeyConversionError < RuntimeError; end
    class UnsupportedVersionError < RuntimeError; end
  end
end
