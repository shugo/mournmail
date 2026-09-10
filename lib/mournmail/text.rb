require "mail"
require "nkf"

module Mournmail
  begin
    require "mail-gpg"
    HAVE_MAIL_GPG = true
  rescue LoadError
    HAVE_MAIL_GPG = false
  end

  def self.escape_binary(s)
    s.b.gsub(/[\x80-\xff]/n) { |c|
      "<%02X>" % c.ord
    }
  end

  def self.decode_eword(s)
    Mail::Encodings.decode_encode(s, :decode).
      encode(Encoding::UTF_8, replace: "?").gsub(/[\t\n]/, " ")
  rescue Encoding::CompatibilityError, Encoding::UndefinedConversionError
    escape_binary(s)
  end

  def self.force_utf8(s)
    s.dup.force_encoding(Encoding::UTF_8).scrub("?")
  end

  def self.to_utf8(s, charset)
    if /\Autf-8\z/i.match?(charset)
      force_utf8(s)
    else
      begin
        s.encode(Encoding::UTF_8, charset, replace: "?")
      rescue
        force_utf8(NKF.nkf("-w", s))
      end
    end.gsub(/\r\n/, "\n")
  end

  def self.parse_mail(s)
    Mail.new(s.scrub("??"))
  end
end
