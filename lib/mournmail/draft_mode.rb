module Mournmail
  class DraftMode < Textbringer::Mode
    MAIL_MODE_MAP = Keymap.new
    MAIL_MODE_MAP.define_key("\C-c\C-c", :draft_send_command)
    MAIL_MODE_MAP.define_key("\C-c\C-k", :draft_kill_command)
    MAIL_MODE_MAP.define_key("\C-c\C-x\C-i", :draft_attach_file_command)
    MAIL_MODE_MAP.define_key("\t", :draft_complete_or_insert_tab_command)
    MAIL_MODE_MAP.define_key("\C-c\C-xv", :draft_pgp_sign_command)
    MAIL_MODE_MAP.define_key("\C-c\C-xe", :draft_pgp_encrypt_command)
    MAIL_MODE_MAP.define_key("\C-c\t", :insert_signature_command)
    MAIL_MODE_MAP.define_key("\C-c@", :draft_change_account_command)

    define_syntax :field_name, /^[A-Za-z\-]+: /
    define_syntax :quotation, /^>.*/
    define_syntax :header_end, /^--text follows this line--$/

    def initialize(buffer)
      super(buffer)
      buffer.keymap = MAIL_MODE_MAP
    end

    define_local_command(:draft_send,
                         doc: "Send a mail and exit from mail buffer.") do
      s = @buffer.to_s
      if s.match?(CONFIG[:mournmail_forgotten_attachment_re]) &&
          !s.match?(/^Attached-File:/)
        msg = "It seems like you forgot to attach a file. Send anyway?"
        return unless yes_or_no?(msg)
      else
        return unless y_or_n?("Send this mail?")
      end
      run_hooks(:mournmail_pre_send_hook)
      charset = CONFIG[:mournmail_charset]
      begin
        s.encode(charset)
      rescue Encoding::UndefinedConversionError
        charset = "utf-8"
      end
      m = Mail.new(charset: charset)
      m.transport_encoding = "8bit"
      header, body = s.split(/^--text follows this line--\n/, 2)
      attached_files = []
      attached_messages = []
      pgp_sign = false
      pgp_encrypt = false
      header.scan(/^([!-9;-~]+):[ \t]*(.*(?:\n[ \t].*)*)\n/) do |name, val|
        case name
        when "Attached-File"
          attached_files.push(val.strip)
        when "Attached-Message"
          attached_messages.push(val.strip)
        when "PGP-Sign"
          pgp_sign = val.strip == "yes"
        when "PGP-Encrypt"
          pgp_encrypt = val.strip == "yes"
        else
          m[name] = val
        end
      end
      if body.empty?
        return if !yes_or_no?("Body is empty.  Really send?")
      else
        if attached_files.empty? && attached_messages.empty?
          m.body = body
        else
          part = Mail::Part.new(content_type: "text/plain", body: body)
          part.charset = charset
          m.body << part
        end
      end
      attached_files.each do |file|
        m.add_file(filename: File.basename(file),
                   content: File.read(file),
                   encoding: "binary")
      end
      account = @buffer[:mournmail_delivery_account] ||
        Mournmail.current_account
      conf = CONFIG[:mournmail_accounts][account]
      delivery_method = @buffer[:mournmail_delivery_method] ||
        conf[:delivery_method]
      options = @buffer[:mournmail_delivery_options] ||
        conf[:delivery_options]
      if delivery_method == :smtp
        options = {
          open_timeout: CONFIG[:mournmail_smtp_open_timeout],
          read_timeout: CONFIG[:mournmail_smtp_read_timeout],
        }.merge(options)
      end
      if options[:authentication] == "gmail"
        token = Mournmail.google_access_token(account)
        options = options.merge(authentication: "xoauth2",
                                password: token)
      end
      m.delivery_method(delivery_method, options)
      bury_buffer(@buffer)
      Mournmail.background do
        begin
          if !attached_messages.empty?
            attached_messages.each do |attached_message|
              cache_id = attached_message.strip
              s = File.read(Mournmail.mail_cache_path(cache_id))
              part = Mail::Part.new(content_type: "message/rfc822", body: s)
              m.body << part
            end
          end
          if pgp_sign || pgp_encrypt
            m.gpg(sign: pgp_sign, encrypt: pgp_encrypt)
          end
          m.deliver
          foreground do
            message("Mail sent.")
          end
          cache_id = Mournmail.write_mail_cache(m.encoded)
          Mournmail.index_mail(cache_id, m)
          outbox = Mournmail.account_config[:outbox_mailbox]
          if outbox
            Mournmail.imap_connect do |imap|
              unless imap.list("", outbox)
                imap.create(outbox)
              end
              imap.append(outbox, m.to_s, [:Seen])
            end
          end
          foreground do
            kill_buffer(@buffer, force: true)
            Mournmail.back_to_summary
          end
        rescue Exception
          foreground do
            switch_to_buffer(@buffer)
          end
          raise
        end
      end
    end
    
    define_local_command(:draft_kill, doc: "Kill the draft buffer.") do
      if yes_or_no?("Kill current draft?")
        kill_buffer(@buffer, force: true)
        Mournmail.back_to_summary
      end
    end
    
    define_local_command(:draft_attach_file, doc: "Attach a file.") do
      |file_name = read_file_name("Attach file: ")|
      @buffer.save_excursion do
        end_of_header
        @buffer.insert("Attached-File: #{file_name}\n")
      end
    end
    
    define_local_command(:draft_complete_or_insert_tab,
                         doc: "Complete a mail address or insert a tab.") do
      is_address_field = @buffer.save_excursion {
        @buffer.beginning_of_line
        @buffer.looking_at?(/(To|Cc|Bcc):/i)
      }
      if is_address_field
        end_pos = @buffer.point
        @buffer.skip_re_backward(/[^ :,]/)
        start_pos = @buffer.point
        s = @buffer.substring(start_pos, end_pos)
        if !s.empty?
          re = /^(?:.*")?#{Regexp.quote(s)}.*/
          addrs = File.read(CONFIG[:mournmail_addresses_path])
            .scan(re).map { |line| line.slice(/^\S+/) }
          if !addrs.empty?
            addr = addrs.inject { |x, y|
              x.chars.zip(y.chars).take_while { |i, j|
                i == j
              }.map { |i,| i }.join
            }
            @buffer.delete_region(start_pos, end_pos)
            @buffer.insert(addr)
          else
            @buffer.goto_char(end_pos)
            message("No match")
          end
        end
      else
        @buffer.insert("\t")
      end
    end
    
    define_local_command(:draft_pgp_sign, doc: "PGP sign.") do
      @buffer.save_excursion do
        end_of_header
        @buffer.insert("PGP-Sign: yes\n")
      end
    end
    
    define_local_command(:draft_pgp_encrypt, doc: "PGP encrypt.") do
      @buffer.save_excursion do
        end_of_header
        @buffer.insert("PGP-Encrypt: yes\n")
      end
    end

    define_local_command(:insert_signature, doc: "Insert signature.") do
      @buffer.insert(CONFIG[:signature])
    end

    define_local_command(:draft_change_account, doc: "Change account.") do
      |account = Mournmail.read_account_name("Change account: ")|
      from = CONFIG[:mournmail_accounts][account][:from]
      @buffer[:mournmail_delivery_account] = account
      @buffer.save_excursion do
        @buffer.beginning_of_buffer
        @buffer.re_search_forward(/^From:.*/)
        @buffer.replace_match("From: " + from)
        @buffer.end_of_buffer
        if @buffer.re_search_backward(CONFIG[:mournmail_signature_regexp],
                                      raise_error: false)
          @buffer.delete_region(@buffer.point, @buffer.point_max)
        end
        Mournmail.insert_signature
      end
    end

    private

    def end_of_header
      @buffer.beginning_of_buffer
      @buffer.re_search_forward(/^--text follows this line--$/)
      @buffer.beginning_of_line
    end
  end
end
