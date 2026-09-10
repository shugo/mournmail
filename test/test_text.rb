require "test/unit"
require "mournmail/text"

class TestText < Test::Unit::TestCase
  def test_escape_binary
    assert_equal("abc", Mournmail.escape_binary("abc"))
    assert_equal("<E3><81><82>", Mournmail.escape_binary("あ"))
    assert_equal("a<FF>b", Mournmail.escape_binary("a\xFFb".b))
  end

  def test_decode_eword_base64
    assert_equal("こんにちは",
                 Mournmail.decode_eword("=?UTF-8?B?44GT44KT44Gr44Gh44Gv?="))
  end

  def test_decode_eword_quoted_printable
    eword = "=?UTF-8?Q?=E3=81=93=E3=82=93=E3=81=AB=E3=81=A1=E3=81=AF?="
    assert_equal("こんにちは", Mournmail.decode_eword(eword))
  end

  def test_decode_eword_iso_2022_jp
    eword = "=?ISO-2022-JP?B?GyRCJDMkcyRLJEEkTxsoQg==?="
    assert_equal("こんにちは", Mournmail.decode_eword(eword))
  end

  def test_decode_eword_replaces_tabs_and_newlines
    assert_equal("a b c", Mournmail.decode_eword("a\tb\nc"))
    # Whitespace between adjacent encoded words is ignored (RFC 2047 6.2).
    assert_equal("foobar",
                 Mournmail.decode_eword("=?UTF-8?B?Zm9v?=\n =?UTF-8?B?YmFy?="))
  end

  def test_decode_eword_plain_text_is_kept
    assert_equal("Re: hello", Mournmail.decode_eword("Re: hello"))
  end

  def test_decode_eword_replaces_invalid_bytes
    assert_equal("a?b", Mournmail.decode_eword("a\xFFb".b))
  end

  def test_force_utf8
    s = Mournmail.force_utf8("\xE3\x81\x82\xFF".b)
    assert_equal(Encoding::UTF_8, s.encoding)
    assert_equal("あ?", s)
  end

  def test_force_utf8_does_not_modify_the_argument
    s = "abc".b
    Mournmail.force_utf8(s)
    assert_equal(Encoding::ASCII_8BIT, s.encoding)
  end

  def test_to_utf8_utf8
    assert_equal("あ\nい", Mournmail.to_utf8("あ\r\nい".b, "utf-8"))
    assert_equal("あ?", Mournmail.to_utf8("\xE3\x81\x82\xFF".b, "UTF-8"))
  end

  def test_to_utf8_iso_2022_jp
    s = "こんにちは".encode("ISO-2022-JP").b
    assert_equal("こんにちは", Mournmail.to_utf8(s, "iso-2022-jp"))
  end

  def test_to_utf8_shift_jis
    s = "こんにちは\r\n".encode("Shift_JIS").b
    assert_equal("こんにちは\n", Mournmail.to_utf8(s, "shift_jis"))
  end

  def test_to_utf8_unknown_charset_falls_back_to_nkf
    s = "こんにちは".encode("EUC-JP").b
    assert_equal("こんにちは", Mournmail.to_utf8(s, "x-unknown"))
  end

  def test_parse_mail
    mail = Mournmail.parse_mail("Subject: hi\r\n\r\nbody\r\n")
    assert_equal("hi", mail.subject)
    assert_equal("body", mail.body.decoded.strip)
  end

  def test_parse_mail_scrubs_invalid_bytes
    mail = Mournmail.parse_mail("Subject: hi\xFF\r\n\r\nbody\r\n")
    assert_equal("hi??", mail.subject)
  end
end
