# frozen_string_literal: true

module Mournmail
  class MessageMode < Textbringer::Mode
    MESSAGE_MODE_MAP = Keymap.new
    MESSAGE_MODE_MAP.define_key("s", :mournmail_message_save_part)

    define_syntax :keyword, /^[A-Za-z\-]+: /
    define_syntax :comment, /^>.*/
    define_syntax :link, /^\[([0-9.]+) [A-Za-z._\-]+\/[A-Za-z._\-]+.*\]$/

    def initialize(buffer)
      super(buffer)
      buffer.keymap = MESSAGE_MODE_MAP
    end
  end
end
