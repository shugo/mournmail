# frozen_string_literal: true

module Mournmail
  class DraftMode < Textbringer::Mode
    MAIL_MODE_MAP = Keymap.new
    MAIL_MODE_MAP.define_key("\C-c\C-c", :mournmail_draft_send)
    MAIL_MODE_MAP.define_key("\C-c\C-k", :mournmail_draft_kill)
    MAIL_MODE_MAP.define_key("\C-ca", :mournmail_draft_attach_file)

    define_syntax :field_name, /^[A-Za-z\-]+: /
    define_syntax :quotation, /^>.*/
    define_syntax :header_end, /^--text follows this line--$/

    def initialize(buffer)
      super(buffer)
      buffer.keymap = MAIL_MODE_MAP
    end
  end
end
