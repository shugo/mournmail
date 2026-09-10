require "test/unit"
require "mail"
require "mournmail/header_folding"

class TestHeaderFolding < Test::Unit::TestCase
  def message_ids(n)
    (1..n).map { |i| "<%04d.abcdefghijklmnopqrstuvwxyz@example.com>" % i }
  end

  def assert_folded_lines(field, max_line_length: 78)
    lines = field.split("\n")
    lines.each do |line|
      assert(line.size <= max_line_length,
             "line too long (#{line.size}): #{line.inspect}")
    end
    lines.drop(1).each do |line|
      assert_match(/\A[ \t]/, line, "continuation line must start with WSP")
      assert_match(/[^ \t]/, line, "continuation line must not be blank")
    end
    assert_no_match(/[ \t]$/, field, "no trailing whitespace on a line")
  end

  def test_short_field_is_not_folded
    assert_equal("Subject: hello",
                 Mournmail.fold_header_field("Subject", "hello"))
  end

  def test_empty_value
    assert_equal("Cc: ", Mournmail.fold_header_field("Cc", ""))
    assert_equal("Cc: ", Mournmail.fold_header_field("Cc", nil))
  end

  def test_references_are_folded_at_whitespace
    ids = message_ids(20)
    value = ids.join(" ")
    field = Mournmail.fold_header_field("References", value)
    assert_match(/\AReferences: </, field)
    assert_folded_lines(field)
    assert(field.count("\n") > 0, "should be folded")
    # Unfolding gives back the original value.
    assert_equal("References: " + value,
                 Mournmail.unfold_header_value(field))
    # Message-IDs are never split.
    assert_equal(ids, field.scan(/<[^>]+>/))
    field.split("\n").each do |line|
      assert_match(/\A(References: |[ \t])(<[^>]+>[ \t])*<[^>]+>\z/, line)
    end
  end

  def test_addresses_are_folded_after_comma
    addrs = (1..10).map { |i| "Taro Yamada #{i} <taro#{i}@example.com>" }
    value = addrs.join(", ")
    field = Mournmail.fold_header_field("Cc", value)
    assert_folded_lines(field)
    assert_equal("Cc: " + value, Mournmail.unfold_header_value(field))
    assert_equal(addrs, Mournmail.unfold_header_value(field).
                        sub(/\ACc: /, "").split(", "))
  end

  def test_long_token_is_not_split
    long = "<" + "x" * 100 + "@example.com>"
    value = "<a@example.com> #{long} <b@example.com>"
    field = Mournmail.fold_header_field("References", value)
    assert_equal(["References: <a@example.com>", " " + long,
                  " <b@example.com>"],
                 field.split("\n"))
  end

  def test_first_token_stays_on_the_first_line
    long = "<" + "x" * 100 + "@example.com>"
    field = Mournmail.fold_header_field("References", "#{long} <b@example.com>")
    assert_equal(["References: " + long, " <b@example.com>"],
                 field.split("\n"))
  end

  def test_fills_lines_greedily
    field = Mournmail.fold_header_field("X", "aa bb cc dd ee",
                                        max_line_length: 8)
    assert_equal(["X: aa bb", " cc dd", " ee"], field.split("\n"))
    field = Mournmail.fold_header_field("X", "aa bb cc dd ee",
                                        max_line_length: 9)
    assert_equal(["X: aa bb", " cc dd ee"], field.split("\n"))
  end

  def test_whitespace_is_preserved
    field = Mournmail.fold_header_field("X", "aa  bb\tcc",
                                        max_line_length: 6)
    assert_equal(["X: aa", "  bb", "\tcc"], field.split("\n"))
    assert_equal("X: aa  bb\tcc", Mournmail.unfold_header_value(field))
  end

  def test_leading_and_trailing_whitespace_are_removed
    assert_equal("X: aa bb", Mournmail.fold_header_field("X", "  aa bb \t"))
  end

  def test_already_folded_value_is_refolded
    ids = message_ids(6)
    value = ids.each_slice(2).map { |s| s.join(" ") }.join("\r\n ")
    field = Mournmail.fold_header_field("References", value)
    assert_folded_lines(field)
    assert_equal("References: " + ids.join(" "),
                 Mournmail.unfold_header_value(field))
  end

  def test_bare_newline_is_treated_as_space
    assert_equal("X: aa bb", Mournmail.fold_header_field("X", "aa\nbb"))
    assert_equal("X: aa bb", Mournmail.fold_header_field("X", "aa\r\nbb"))
  end

  def test_unfold_header_value
    assert_equal("aa bb\tcc", Mournmail.unfold_header_value("aa\n bb\r\n\tcc"))
    assert_equal("aa\nbb", Mournmail.unfold_header_value("aa\nbb"))
    assert_equal("", Mournmail.unfold_header_value(nil))
  end

  def test_folded_field_is_accepted_by_mail
    ids = message_ids(20)
    field = Mournmail.fold_header_field("References", ids.join(" "))
    name, value = field.split(/:[ \t]*/, 2)
    m = Mail.new
    m["From"] = "from@example.com"
    m["To"] = "to@example.com"
    m["Subject"] = "test"
    m[name] = Mournmail.unfold_header_value(value)
    m.body = "hello"
    assert_equal(ids.map { |id| id[1..-2] }, m.references)
    encoded = m.encoded
    assert_no_match(/(?<!\r)\n/, encoded, "bare LF in encoded message")
    header = encoded.split("\r\n\r\n", 2).first
    header.split("\r\n").each do |line|
      assert(line.size <= 78, "line too long (#{line.size}): #{line.inspect}")
    end
    assert_equal(ids.map { |id| id[1..-2] }, Mail.new(encoded).references)
  end
end
