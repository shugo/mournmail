require_relative "plugin_helper"
require_relative "fake_imap"

class TestFetchSummary < Mournmail::PluginTestCase
  FETCH_ATTRS = ["UID", "ENVELOPE", "FLAGS"]

  def test_fetch_new_mailbox
    imap = FakeIMAP.new(uidvalidity: 7)
    imap.add_message(1, subject: "first", flags: [:Seen])
    imap.add_message(2, subject: "second",
                     from: [FakeIMAP.address("Bob", "bob")],
                     in_reply_to: "<1@example.com>")
    summary = with_imap(imap) { Mournmail.fetch_summary("INBOX") }
    assert_equal("INBOX", summary.mailbox)
    assert_equal([1, 2], summary.uids)
    assert_equal(7, summary.uidvalidity)
    assert_equal("first", summary[1].subject)
    assert_equal([:Seen], summary[1].flags)
    assert_equal("Bob", summary[2].from[0].name)
    assert_equal([], summary[2].flags)
    assert_equal([[:select, "INBOX"],
                  [:uid_search, "ALL"],
                  [:uid_fetch, [1, 2], FETCH_ATTRS]],
                 imap.calls)
    # Nothing is saved until the caller asks for it.
    assert(!File.exist?(Mournmail::Summary.cache_path("INBOX")))
  end

  def test_fetch_only_new_messages
    imap = FakeIMAP.new
    imap.add_message(1).add_message(2)
    summary = with_imap(imap) { Mournmail.fetch_summary("INBOX") }
    summary.save

    imap.add_message(3, subject: "third")
    imap.calls.clear
    summary = with_imap(imap) { Mournmail.fetch_summary("INBOX") }
    assert_equal([1, 2, 3], summary.uids)
    assert_equal("third", summary[3].subject)
    assert_equal([[:uid_fetch, [3], FETCH_ATTRS]], imap.calls_of(:uid_fetch))
    summary.save

    imap.calls.clear
    summary = with_imap(imap) { Mournmail.fetch_summary("INBOX") }
    assert_equal([1, 2, 3], summary.uids)
    assert_equal([], imap.calls_of(:uid_fetch))
  end

  def test_fetch_all_ignores_the_cache
    imap = FakeIMAP.new
    imap.add_message(1)
    summary = with_imap(imap) { Mournmail.fetch_summary("INBOX") }
    summary.save
    imap.calls.clear
    summary = with_imap(imap) { Mournmail.fetch_summary("INBOX", all: true) }
    assert_equal([1], summary.uids)
    assert_equal([[:uid_fetch, [1], FETCH_ATTRS]], imap.calls_of(:uid_fetch))
  end

  def test_fetch_in_chunks
    imap = FakeIMAP.new
    (1..1500).each { |uid| imap.add_message(uid) }
    summary = with_imap(imap) { Mournmail.fetch_summary("INBOX") }
    assert_equal(1500, summary.uids.size)
    assert_equal(1500, summary.last_uid)
    assert_equal([1000, 500],
                 imap.calls_of(:uid_fetch).map { |call| call[1].size })
  end

  def test_network_error_returns_the_summary_so_far
    imap = FakeIMAP.new
    imap.add_message(1)
    summary = with_imap(imap) { Mournmail.fetch_summary("INBOX") }
    summary.save
    imap.define_singleton_method(:uid_search) { |*| raise SocketError, "down" }
    summary = with_imap(imap) { Mournmail.fetch_summary("INBOX") }
    assert_equal([1], summary.uids)
  end
end
