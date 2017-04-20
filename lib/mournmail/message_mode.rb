# frozen_string_literal: true

module Mournmail
  class MessageMode < Textbringer::Mode
    define_syntax :keyword, /^[A-Za-z\-]+: /
    define_syntax :comment, /^>.*/
  end
end
