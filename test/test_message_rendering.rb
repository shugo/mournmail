require "test/unit"
require "mail"
require "mournmail/text"
require "mournmail/message_rendering"

using Mournmail::MessageRendering

class TestMessageRendering < Test::Unit::TestCase
  def mail(s)
    Mail.new(s.gsub(/\n/, "\r\n"))
  end

  def mixed_mail
    mail(<<~EOF)
      From: a@example.com
      To: b@example.com
      Subject: hi\tthere
      Content-Type: multipart/mixed; boundary="outer"

      --outer
      Content-Type: multipart/alternative; boundary="inner"

      --inner
      Content-Type: text/plain; charset=UTF-8

      plain body
      --inner
      Content-Type: text/html; charset=UTF-8

      <html><body><p>html body</p></body></html>
      --inner--
      --outer
      Content-Type: image/png; name="=?UTF-8?B?55S75YOPLnBuZw==?="
      Content-Disposition: attachment; filename="=?UTF-8?B?55S75YOPLnBuZw==?="
      Content-Transfer-Encoding: base64

      iVBORw0KGgo=
      --outer--
    EOF
  end

  def test_render_header_uses_the_given_fields_in_order
    m = mixed_mail
    assert_equal("From: a@example.com\nSubject: hi there\n",
                 m.render_header(["From", "Subject", "X-Missing"]))
  end

  def test_render_body_plain_text
    m = mail("Subject: x\nContent-Type: text/plain; charset=UTF-8\n\nbody\n")
    assert_equal("body\n", m.render_body)
  end

  def test_render_body_without_content_type
    m = mail("Subject: x\n\nbare body\n")
    assert_equal("bare body\n", m.render_body)
  end

  def test_render_body_converts_charset
    m = mail("Subject: x\nContent-Type: text/plain; charset=ISO-2022-JP\n\n" +
             "こんにちは".encode("ISO-2022-JP").b + "\n")
    assert_equal("こんにちは\n", m.render_body)
  end

  def test_render_body_html_drops_script_and_style
    m = mail("Content-Type: text/html; charset=UTF-8\n\n" +
             "<html><head><style>p{}</style><script>alert(1)</script>" +
             "</head><body><p>html   body</p><p>more</p></body></html>\n")
    assert_equal("[0 text/html]\nhtml bodymore", m.render_body)
  end

  def test_render_body_non_text_single_part
    m = mail("Content-Type: application/pdf; name=\"x.pdf\"\n" +
             "Content-Transfer-Encoding: base64\n\nAAAA\n")
    assert_equal("[0 application/pdf; name=x.pdf]\n", m.render_body)
  end

  def test_render_body_multipart
    expected = <<~EOF
      [1 multipart/alternative; boundary=inner]
      [1.1 text/plain; charset=UTF-8]
      plain body
      [1.2 text/html; charset=UTF-8]
      [2 image/png; name="画像.png"]
    EOF
    assert_equal(expected, mixed_mail.render_body)
  end

  def test_render_body_shows_disposition_filename
    m = mail(<<~EOF)
      Content-Type: multipart/mixed; boundary="b"

      --b
      Content-Type: application/octet-stream
      Content-Disposition: attachment; filename="a.bin"

      AAA
      --b--
    EOF
    assert_equal("[1 application/octet-stream; filename=a.bin]\n",
                 m.render_body)
  end

  def test_render_text_takes_only_the_first_alternative
    assert_equal("plain body\n\n\n", mixed_mail.render_text)
  end

  def test_render_text_converts_html
    m = mail("Content-Type: text/html; charset=UTF-8\n\n" +
             "<html><body><p>html body</p><p>more</p></body></html>\n")
    assert_equal("html body\n\nmore", m.render_text)
  end

  def test_dig_part
    m = mixed_mail
    assert_same(m, m.dig_part(0))
    assert_equal("multipart/alternative; boundary=inner",
                 m.dig_part(1).content_type)
    assert_equal("text/plain; charset=UTF-8", m.dig_part(1, 1).content_type)
    assert_equal("text/html; charset=UTF-8", m.dig_part(1, 2).content_type)
    assert_equal("画像.png", m.dig_part(2).filename)
  end

  def test_dig_part_into_rfc822
    m = mail(<<~EOF)
      Subject: fwd
      Content-Type: multipart/mixed; boundary="b"

      --b
      Content-Type: text/plain

      see attached
      --b
      Content-Type: message/rfc822

      Subject: inner
      Content-Type: text/plain

      inner body
      --b--
    EOF
    assert_equal("inner", m.dig_part(2, 0).subject)
  end
end
