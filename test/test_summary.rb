require_relative "plugin_helper"
require_relative "fake_imap"

class TestSummary < Mournmail::PluginTestCase
  def item(uid, flags: [:Seen], from: [FakeIMAP.address("Alice", "alice")],
           subject: "hello", date: "Mon, 1 Sep 2025 10:00:00 +0000")
    Mournmail::SummaryItem.new(uid, date, from, subject, flags)
  end

  def summary_with(*items)
    summary = Mournmail::Summary.new("INBOX")
    items.each_with_index do |i, n|
      summary.add_item(i, "<#{i.uid}@example.com>",
                       n > 0 ? "<#{items[n - 1].uid}@example.com>" : nil)
    end
    summary
  end

  # The width of everything before the subject with the default limits.
  SUBJECT_WIDTH = 78 - "     1  09/01 10:00 [ Alice <alice@exa ] ".size

  def test_add_item
    summary = summary_with(item(3), item(7))
    assert_equal([3, 7], summary.uids)
    assert_equal(7, summary.last_uid)
    assert_equal("hello", summary[3].subject)
    assert_nil(summary[4])
    assert_equal([3, 7], summary.items.map(&:uid))
  end

  def test_delete_item_if
    summary = summary_with(item(1), item(2, flags: [:Seen, :Deleted]),
                           item(3))
    summary.delete_item_if { |i| i.flags.include?(:Deleted) }
    assert_equal([1, 3], summary.items.map(&:uid))
  end

  def test_save_and_load
    summary = summary_with(item(1), item(2, flags: []))
    summary.uidvalidity = 42
    summary[1].cache_id = "abc"
    summary.save
    path = Mournmail::Summary.cache_path("INBOX")
    assert_equal(File.join(@tmpdir, "cache/test/mailboxes/INBOX/.summary"),
                 path)
    assert(File.exist?(path))
    assert(File.exist?(path + ".lock"))
    assert(!File.exist?(path + ".tmp"))

    loaded = Mournmail::Summary.load("INBOX")
    assert_equal("INBOX", loaded.mailbox)
    assert_equal([1, 2], loaded.uids)
    assert_equal(2, loaded.last_uid)
    assert_equal(42, loaded.uidvalidity)
    assert_equal("abc", loaded[1].cache_id)
    assert_equal([], loaded[2].flags)
    assert_equal(summary.to_s, loaded.to_s)
    # The monitor is rebuilt on load.
    loaded.synchronize { }

    summary.save
    assert(File.exist?(path + ".old"))
  end

  def test_load_or_new
    summary = Mournmail::Summary.load_or_new("INBOX")
    assert_equal([], summary.uids)
    assert_nil(summary.last_uid)
    assert_raise(Errno::ENOENT) { Mournmail::Summary.load("INBOX") }
  end

  def test_to_s
    summary = summary_with(item(1), item(23, flags: []))
    assert_equal("     1  09/01 10:00 [ Alice <alice@exa ] " +
                 "hello".ljust(SUBJECT_WIDTH) + "\n" +
                 "    23 u09/01 10:00 [ Alice <alice@exa ] " +
                 "hello".ljust(SUBJECT_WIDTH) + "\n",
                 summary.to_s)
  end

  def test_flags_char
    assert_equal("u", item(1, flags: []).flags_char)
    assert_equal("u", item(1, flags: [:Flagged]).flags_char)
    assert_equal("d", item(1, flags: [:Seen, :Flagged, :Deleted]).flags_char)
    assert_equal("$", item(1, flags: [:Seen, :Answered, :Flagged]).flags_char)
    assert_equal("a", item(1, flags: [:Seen, :Answered]).flags_char)
    assert_equal(" ", item(1, flags: [:Seen]).flags_char)
  end

  def test_date_is_shown_in_local_time
    line = item(1, date: "Mon, 1 Sep 2025 10:00:00 +0900").to_s
    assert_match(/\A     1  09\/01 01:00 /, line)
  end

  def test_invalid_date_becomes_epoch
    line = item(1, date: "not a date").to_s
    assert_match(/\A     1  01\/01 00:00 /, line)
  end

  def test_from_without_name
    line = item(1, from: [FakeIMAP.address(nil, "alice")]).to_s
    assert_match(/\[ alice@example\.co \]/, line)
  end

  def test_unknown_sender
    assert_match(/\[ Unknown sender   \]/, item(1, from: nil).to_s)
    address = Net::IMAP::Address.new(nil, nil, nil, nil)
    assert_match(/\[ Unknown sender   \]/, item(1, from: [address]).to_s)
  end

  def test_encoded_words_are_decoded
    from = [FakeIMAP.address("=?UTF-8?B?5bGx55Sw?=", "taro")]
    line = item(1, from: from,
                subject: "=?UTF-8?B?44GT44KT44Gr44Gh44Gv?=").to_s
    assert_match(/\[ 山田 <taro@examp \] こんにちは /, line)
  end

  def test_binary_in_address_is_escaped
    line = item(1, from: [FakeIMAP.address(nil, "a\xFFb".b)]).to_s
    assert_match(/\[ a<FF>b@example\.c \]/, line)
  end

  def test_wide_characters_are_truncated_by_display_width
    from = [FakeIMAP.address("山田 太郎", "taro")]
    line = item(1, from: from, subject: "あ" * 40).to_s
    assert_match(/\[ 山田 太郎 <taro@ \] /, line)
    assert_equal(78, Buffer.display_width(line.chomp))
    assert_equal("あ" * (SUBJECT_WIDTH / 2) + " ",
                 line.chomp[/\] (.*)\z/, 1])
  end

  def test_thread_indentation
    parent = item(1)
    child = item(2)
    parent.add_reply(child)
    lines = parent.to_s.lines
    assert_equal(2, lines.size)
    assert_match(/\A     2  09\/01 10:00   \[ /, lines[1])
  end

  def test_line_cache_is_updated_by_flag_changes
    i = item(1, flags: [])
    assert_match(/\A     1 u/, i.to_s)
    i.set_flag(:Seen, update_server: false)
    assert_equal([:Seen], i.flags)
    assert_match(/\A     1  /, i.to_s)
    i.toggle_flag(:Flagged, update_server: false)
    assert_match(/\A     1 \$/, i.to_s)
    i.unset_flag(:Flagged, update_server: false)
    assert_match(/\A     1  /, i.to_s)
    # Setting a flag that is already set changes nothing.
    i.set_flag(:Seen, update_server: false)
    assert_equal([:Seen], i.flags)
  end

  def test_to_s_without_line_cache
    CONFIG[:mournmail_summary_use_line_cache] = false
    i = item(1, flags: [])
    assert_match(/\A     1 u/, i.to_s)
    i.set_flag(:Seen, update_server: false)
    assert_match(/\A     1  /, i.to_s)
  end

  def test_flag_update_on_server
    imap = FakeIMAP.new.add_message(1, flags: [:Seen])
    i = item(1)
    with_imap(imap) do
      i.toggle_flag(:Flagged)
    end
    assert_equal([[:uid_store, 1, "+FLAGS", [:Flagged]]], imap.calls)
    assert_equal([:Seen, :Flagged], i.flags)
    assert_match(/\A     1 \$/, i.to_s)
    with_imap(imap) do
      i.toggle_flag(:Flagged)
    end
    assert_equal([:uid_store, 1, "-FLAGS", [:Flagged]], imap.calls.last)
    assert_equal([:Seen], i.flags)
  end

  def test_flag_update_without_server_response
    imap = FakeIMAP.new.add_message(1, flags: [:Seen])
    imap.store_returns_nil = true
    i = item(1)
    with_imap(imap) do
      i.set_flag(:Flagged)
    end
    assert_equal([:Seen, :Flagged], i.flags)
  end

  def test_read_mail_fetches_and_caches
    with_groonga
    raw = raw_mail(subject: "fetched", body: "hello world\r\n")
    imap = FakeIMAP.new.add_message(1, body: raw)
    summary = summary_with(item(1))
    mail, fetched, virus = with_imap(imap) { summary.read_mail(1) }
    assert_equal("fetched", mail.subject)
    assert_true(fetched)
    assert_nil(virus)
    assert_equal([[:select, "INBOX"], [:uid_fetch, 1, "BODY[]"]], imap.calls)
    cache_id = summary[1].cache_id
    assert_not_nil(cache_id)
    assert_equal(raw, Mournmail.read_mail_cache(cache_id))
    assert_equal("fetched", Groonga["Messages"][cache_id].subject)

    # The second read comes from the cache and does not touch IMAP.
    mail, fetched, virus = with_imap(nil) { summary.read_mail(1) }
    assert_equal("fetched", mail.subject)
    assert_false(fetched)
    assert_nil(virus)
  end

  def test_read_mail_raises_when_the_server_has_no_such_mail
    imap = FakeIMAP.new
    summary = summary_with(item(1))
    assert_raise(EditorError) do
      with_imap(imap) { summary.read_mail(1) }
    end
  end

  def test_read_mail_does_not_cache_spam
    with_groonga
    imap = FakeIMAP.new.add_message(1, body: raw_mail)
    summary = Mournmail::Summary.new(Net::IMAP.encode_utf7("Junk"))
    summary.add_item(item(1), "<1@example.com>", nil)
    mail, fetched, = with_imap(imap) { summary.read_mail(1) }
    assert_equal("hello", mail.subject)
    assert_true(fetched)
    assert_nil(summary[1].cache_id)
    assert_equal(0, Groonga["Messages"].size)
  end

  def test_read_mail_does_not_cache_a_virus
    with_groonga
    imap = FakeIMAP.new.add_message(1, body: raw_mail)
    summary = summary_with(item(1))
    scanned = nil
    hook = ->(data) {
      scanned = data
      raise Mournmail::VirusDetected.new("EICAR")
    }
    HOOKS[:mournmail_virus_scan_hook].push(hook)
    begin
      mail, fetched, virus = with_imap(imap) { summary.read_mail(1) }
    ensure
      HOOKS[:mournmail_virus_scan_hook].delete(hook)
    end
    assert_equal("hello", mail.subject)
    assert_true(fetched)
    assert_equal("EICAR", virus)
    assert_equal(imap.messages[1].body, scanned)
    assert_nil(summary[1].cache_id)
    assert_equal(0, Groonga["Messages"].size)
  end

  def test_read_mail_ignores_a_broken_virus_scanner
    with_groonga
    imap = FakeIMAP.new.add_message(1, body: raw_mail)
    summary = summary_with(item(1))
    hook = ->(data) { raise "scanner is down" }
    HOOKS[:mournmail_virus_scan_hook].push(hook)
    begin
      mail, fetched, virus = with_imap(imap) { summary.read_mail(1) }
    ensure
      HOOKS[:mournmail_virus_scan_hook].delete(hook)
    end
    assert_nil(virus)
    assert_not_nil(summary[1].cache_id)
  end
end
