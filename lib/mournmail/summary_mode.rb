# frozen_string_literal: true

module Mournmail
  class SummaryMode < Textbringer::Mode
    SUMMARY_MODE_MAP = Keymap.new
    SUMMARY_MODE_MAP.define_key(" ", :mournmail_summary_read)
    SUMMARY_MODE_MAP.define_key("q", :mournmail_quit)

    def initialize(buffer)
      super(buffer)
      buffer.keymap = SUMMARY_MODE_MAP
    end
  end
end
