# frozen_string_literal: true

using Mournmail::MessageRendering

module Mournmail
  class SearchResultMode < Mournmail::SummaryMode
    SEARCH_RESULT_MODE_MAP = Keymap.new
    SEARCH_RESULT_MODE_MAP.define_key(" ", :summary_read_command)
    SEARCH_RESULT_MODE_MAP.define_key(:backspace, :summary_scroll_down_command)
    SEARCH_RESULT_MODE_MAP.define_key("\C-h", :summary_scroll_down_command)
    SEARCH_RESULT_MODE_MAP.define_key("\C-?", :summary_scroll_down_command)
    SEARCH_RESULT_MODE_MAP.define_key("w", :summary_write_command)
    SEARCH_RESULT_MODE_MAP.define_key("a", :summary_reply_command)
    SEARCH_RESULT_MODE_MAP.define_key("A", :summary_reply_command)
    SEARCH_RESULT_MODE_MAP.define_key("f", :summary_forward_command)
    SEARCH_RESULT_MODE_MAP.define_key("v", :summary_view_source_command)
    SEARCH_RESULT_MODE_MAP.define_key("q", :search_result_close_command)
    SEARCH_RESULT_MODE_MAP.define_key("k", :previous_line)
    SEARCH_RESULT_MODE_MAP.define_key("j", :next_line)
    SEARCH_RESULT_MODE_MAP.define_key("<", :previous_page_command)
    SEARCH_RESULT_MODE_MAP.define_key(">", :next_page_command)
    SEARCH_RESULT_MODE_MAP.define_key("/", :summary_search_command)
    SEARCH_RESULT_MODE_MAP.define_key("t", :summary_show_thread_command)
    SEARCH_RESULT_MODE_MAP.define_key("@", :summary_change_account_command)

    def initialize(buffer)
      super(buffer)
      buffer.keymap = SEARCH_RESULT_MODE_MAP
    end

    define_local_command(:summary_read, doc: "Read a mail.") do
      num = scroll_up_or_current_number
      return if num.nil?
      Mournmail.background do
        message = @buffer[:messages][num]
        if message.nil? || message._key.nil?
          raise EditorError, "No message found"
        end
        mail = Mail.new(Mournmail.read_mail_cache(message._key))
        foreground do
          show_message(mail)
          @buffer[:message_number] = num
        end
      end
    end

    define_local_command(:summary_scroll_down,
                         doc: "Scroll down the current message.") do
      num = @buffer.current_line
      if num == @buffer[:message_number]
        window = Mournmail.message_window
        if window.buffer.name == "*message*"
          old_window = Window.current
          begin
            Window.current = window
            scroll_down
            return
          ensure
            Window.current = old_window
          end
        end
      end
    end

    define_local_command(:search_result_close,
                         doc: "Close the search result.") do
      if @buffer.name == "*thread*"
        buf = Buffer["*search result*"] || "*summary*"
      else
        buf = "*summary*"
      end
      kill_buffer(@buffer)
      switch_to_buffer(buf)
    end

    define_local_command(:previous_page,
                         doc: "Show the previous page.") do
      messages = @buffer[:messages]
      page = messages.current_page - 1
      if page < 1
        raise EditorError, "No more page."
      end
      summary_search(@buffer[:query], page)
    end

    define_local_command(:next_page,
                         doc: "Show the next page.") do
      messages = @buffer[:messages]
      page = messages.current_page + 1
      if page > messages.n_pages
        raise EditorError, "No more page."
      end
      summary_search(@buffer[:query], page)
    end

    private

    def scroll_up_or_current_number
      begin
        num = @buffer.current_line
        if num == @buffer[:message_number]
          window = Mournmail.message_window
          if window.buffer.name == "*message*"
            old_window = Window.current
            begin
              Window.current = window
              scroll_up
              return nil
            ensure
              Window.current = old_window
            end
          end
        end
        num
      rescue RangeError # may be raised by scroll_up
        next_message
        retry
      end
    end

    def read_current_mail
      message = @buffer[:messages][@buffer.current_line]
      if message.nil?
        raise EditorError, "No message found"
      end
      [Mail.new(Mournmail.read_mail_cache(message._key)), false]
    end

    def next_message
      @buffer.end_of_line
      if @buffer.end_of_buffer?
        raise EditorError, "No more mail"
      end
      @buffer.forward_line
    end

    def current_message
      message = @buffer[:messages][@buffer.current_line]
      if message.nil?
        raise EditorError, "No message found"
      end
      message
    end
  end
end
