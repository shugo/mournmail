# frozen_string_literal: true

module Mournmail
  class MessageMode < Textbringer::Mode
    MESSAGE_MODE_MAP = Keymap.new
    MESSAGE_MODE_MAP.define_key("s", :mournmail_message_save_part)

    define_syntax :field_name, /^[A-Za-z\-]+: /
    define_syntax :quotation, /^>.*/
    define_syntax :mime_part, /^\[([0-9.]+) [A-Za-z._\-]+\/[A-Za-z._\-]+.*\]$/

    def initialize(buffer)
      super(buffer)
      buffer.keymap = MESSAGE_MODE_MAP
    end
  end
end
