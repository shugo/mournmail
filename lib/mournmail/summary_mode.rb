# frozen_string_literal: true

module Mournmail
  class SummaryMode < Textbringer::Mode
    SUMMARY_MODE_MAP = Keymap.new
    SUMMARY_MODE_MAP.define_key("s", :mournmail_summary_sync)
    SUMMARY_MODE_MAP.define_key(" ", :mournmail_summary_read)
    SUMMARY_MODE_MAP.define_key(:backspace, :mournmail_summary_scroll_down)
    SUMMARY_MODE_MAP.define_key("\C-h", :mournmail_summary_scroll_down)
    SUMMARY_MODE_MAP.define_key("\C-?", :mournmail_summary_scroll_down)
    SUMMARY_MODE_MAP.define_key("w", :mournmail_summary_write)
    SUMMARY_MODE_MAP.define_key("a", :mournmail_summary_reply)
    SUMMARY_MODE_MAP.define_key("A", :mournmail_summary_reply)
    SUMMARY_MODE_MAP.define_key("q", :mournmail_quit)
    SUMMARY_MODE_MAP.define_key("k", :previous_line)
    SUMMARY_MODE_MAP.define_key("j", :next_line)

    define_syntax :seen, /^\d+  .*/
    define_syntax :unseen, /^\d+ u.*/
    define_syntax :flagged, /^\d+ \$.*/

    def initialize(buffer)
      super(buffer)
      buffer.keymap = SUMMARY_MODE_MAP
    end
  end
end
