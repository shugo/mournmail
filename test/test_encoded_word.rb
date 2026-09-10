require "test/unit"
require "mail"
require "mournmail/mail_encoded_word_patch"

class TestEncodedWord < Test::Unit::TestCase
  def encoded_subject_lines(subject, charset: "UTF-8")
    m = Mail.new(charset: charset)
    m["From"] = "from@example.com"
    m["To"] = "to@example.com"
    m.subject = subject
    m.body = "hello"
    header = m.encoded.split("\r\n\r\n", 2).first
    lines = header.split("\r\n")
    i = lines.index { |line| line.start_with?("Subject:") }
    field = lines[i..].take_while.with_index { |line, j|
      j == 0 || line.start_with?(" ") || line.start_with?("\t")
    }
    [m, field]
  end

  def assert_round_trip(m, subject)
    assert_equal(subject, Mail.new(m.encoded).subject)
  end

  def test_japanese_subject_is_b_encoded
    subject = "テスト"
    m, lines = encoded_subject_lines(subject)
    assert_equal(1, lines.size)
    assert_match(/\ASubject: =\?UTF-8\?B\?[A-Za-z0-9+\/=]+\?=\z/, lines[0])
    assert_round_trip(m, subject)
  end

  def test_long_japanese_subject_is_folded
    subject = "日本語の長い件名" * 8
    m, lines = encoded_subject_lines(subject)
    assert(lines.size > 1, "should be folded")
    lines.each do |line|
      assert(line.bytesize <= 78, "line too long: #{line.inspect}")
      assert_match(/\A(Subject: |[ \t])=\?UTF-8\?B\?[A-Za-z0-9+\/=]+\?=\z/,
                   line)
    end
    assert_round_trip(m, subject)
  end

  def test_mixed_ascii_and_japanese
    subject = "Re: [ruby-dev:12345] 日本語 subject と English words " +
      "が混ざった長い件名です"
    m, lines = encoded_subject_lines(subject)
    lines.each do |line|
      assert(line.bytesize <= 78, "line too long: #{line.inspect}")
    end
    assert_no_match(/=\?UTF-8\?Q\?/, lines.join)
    assert_round_trip(m, subject)
  end

  def test_ascii_subject_is_not_encoded
    m, lines = encoded_subject_lines("plain ascii subject")
    assert_equal(["Subject: plain ascii subject"], lines)
    assert_round_trip(m, "plain ascii subject")
  end

  def test_non_japanese_text_uses_q_encoding
    subject = "Grüße aus Köln"
    m, lines = encoded_subject_lines(subject)
    assert_match(/=\?UTF-8\?Q\?/, lines.join)
    assert_round_trip(m, subject)
  end

  def test_japanese_in_iso_2022_jp_charset_uses_default_folding
    subject = "テスト"
    m, lines = encoded_subject_lines(subject, charset: "ISO-2022-JP")
    assert_no_match(/=\?UTF-8\?B\?/, lines.join)
    assert_round_trip(m, subject)
  end

  def test_japanese_address_display_name
    m = Mail.new(charset: "UTF-8")
    m["From"] = "from@example.com"
    m["To"] = "山田 太郎 <taro@example.com>"
    m.subject = "hi"
    m.body = "hello"
    parsed = Mail.new(m.encoded)
    assert_equal(["taro@example.com"], parsed.to)
    assert_equal("山田 太郎", parsed[:to].display_names.first)
  end
end
