require_relative "plugin_helper"

# Rendering that reads CONFIG: the default header fields of render and
# the quoted headers of an embedded message/rfc822 part.
class TestRenderMessage < Mournmail::PluginTestCase
  using Mournmail::MessageRendering

  def forwarded_mail
    body = <<~EOF.gsub(/\n/, "\r\n")
      --b
      Content-Type: text/plain

      see attached
      --b
      Content-Type: message/rfc822

      From: Carol <carol@example.com>
      To: alice@example.com
      Subject: inner
      Date: Tue, 2 Sep 2025 09:00:00 +0000
      Content-Type: text/plain

      inner body
      --b--
    EOF
    Mail.new(raw_mail(subject: "fwd",
                      content_type: "multipart/mixed; boundary=\"b\"",
                      body: body))
  end

  def test_render_uses_the_configured_header_fields
    CONFIG[:mournmail_display_header_fields] = ["Subject", "From"]
    m = Mail.new(raw_mail(subject: "hi", body: "text\r\n"))
    assert_equal("Subject: hi\nFrom: Alice <alice@example.com>\n\ntext\n",
                 m.render)
  end

  def test_render_body_of_an_embedded_message
    CONFIG[:mournmail_display_header_fields] = ["Subject", "From"]
    expected = <<~EOF
      [1 text/plain]
      see attached
      [2 message/rfc822]
      Subject: inner
      From: Carol <carol@example.com>

      inner body
    EOF
    assert_equal(expected.chomp, forwarded_mail.render_body)
  end

  def test_render_text_quotes_the_configured_headers
    CONFIG[:mournmail_quote_header_fields] = ["Subject", "Date"]
    expected = "see attached\n\n" +
      "Subject: inner\nDate: Tue, 02 Sep 2025 09:00:00 +0000\n\ninner body"
    assert_equal(expected, forwarded_mail.render_text)
  end
end
