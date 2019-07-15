module Glossator
  class NoOpTranslator < Translator
    def translate(_mode, data)
      data
    end
  end
end
