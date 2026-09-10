require_relative "plugin_helper"
require "digest"

class TestMailCache < Mournmail::PluginTestCase
  def test_write_and_read
    raw = raw_mail(subject: "cached", body: "body\r\n")
    cache_id = Mournmail.write_mail_cache(raw)
    header = raw[0, raw.index("\r\n\r\n") + 4]
    assert_equal(Digest::SHA256.hexdigest(header), cache_id)
    path = Mournmail.mail_cache_path(cache_id)
    assert_equal(File.join(@tmpdir, "cache/test/mails", cache_id[0, 2],
                           cache_id),
                 path)
    assert_equal(raw, File.binread(path))
    assert_equal(raw, Mournmail.read_mail_cache(cache_id))
    assert_equal([], Dir.children(File.dirname(path)) - [cache_id],
                 "no temporary file is left behind")
  end

  def test_binary_body_is_kept
    raw = raw_mail(body: "\x00\xFF\r\n".b)
    cache_id = Mournmail.write_mail_cache(raw)
    assert_equal(raw, Mournmail.read_mail_cache(cache_id).b)
  end

  def test_same_header_gives_same_id
    a = raw_mail(message_id: "<same@example.com>", body: "a\r\n")
    b = raw_mail(message_id: "<same@example.com>", body: "b\r\n")
    assert_equal(Mournmail.write_mail_cache(a), Mournmail.write_mail_cache(b))
    assert_not_equal(Mournmail.write_mail_cache(a),
                     Mournmail.write_mail_cache(raw_mail))
  end

  def test_read_missing_cache
    assert_raise(Errno::ENOENT) { Mournmail.read_mail_cache("0" * 64) }
  end

  def test_paths_depend_on_the_account
    CONFIG[:mournmail_accounts]["other"] = {}
    Mournmail.current_account = "other"
    assert_equal(File.join(@tmpdir, "cache/other/mails/ab/abcd"),
                 Mournmail.mail_cache_path("abcd"))
    assert_equal(File.join(@tmpdir, "cache/other/mailboxes/INBOX"),
                 Mournmail.mailbox_cache_path("INBOX"))
  end
end
