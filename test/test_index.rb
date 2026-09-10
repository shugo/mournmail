require_relative "plugin_helper"

class TestIndex < Mournmail::PluginTestCase
  def setup
    super
    with_groonga
  end

  def index(cache_id, raw)
    mail = Mournmail.parse_mail(raw)
    Mournmail.index_mail(cache_id, mail)
    Groonga["Messages"][cache_id]
  end

  def test_database_is_created_under_the_directory
    assert(File.exist?(File.join(@tmpdir, "groonga/test/messages.db")))
    assert_not_nil(Groonga["Messages"])
    assert_not_nil(Groonga["Terms"])
  end

  def test_indexed_columns
    record = index("id1", raw_mail(message_id: "<m1@example.com>",
                                   subject: "hello", to: "bob@example.com",
                                   cc: "carol@example.com",
                                   list_id: "<dev.example.com>",
                                   body: "body text\r\n"))
    assert_equal("m1@example.com", record.message_id)
    assert_equal("m1@example.com", record.thread_id)
    assert_equal(Time.utc(2025, 9, 1, 10, 0, 0), record.date)
    assert_equal("hello", record.subject)
    assert_equal("Alice <alice@example.com>", record.from)
    assert_equal("bob@example.com", record.to)
    assert_equal("carol@example.com", record.cc)
    assert_equal("<dev.example.com>", record.list_id)
    assert_equal("body text\n", record.body)
  end

  def test_list_id_falls_back_to_x_ml_name
    record = index("id1", raw_mail(x_ml_name: "ruby-dev"))
    assert_equal("ruby-dev", record.list_id)
  end

  def test_thread_id_of_a_reply
    index("id1", raw_mail(message_id: "<root@example.com>"))
    reply = index("id2", raw_mail(message_id: "<reply@example.com>",
                                  in_reply_to: "<root@example.com>"))
    assert_equal("root@example.com", reply.thread_id)
    nested = index("id3", raw_mail(message_id: "<nested@example.com>",
                                   references: "<root@example.com> " +
                                               "<reply@example.com>"))
    assert_equal("root@example.com", nested.thread_id)
  end

  def test_thread_id_of_a_reply_to_an_unknown_message
    record = index("id1", raw_mail(message_id: "<reply@example.com>",
                                   in_reply_to: "<unknown@example.com>"))
    assert_equal("reply@example.com", record.thread_id)
  end

  def test_thread_id_of_redmine_notifications
    record = index("id1", raw_mail(message_id: "<x@example.com>",
                                   references: "<redmine.issue-12.20250901" +
                                               "@example.com>"))
    assert_equal("redmine.issue-12.20250901@example.com", record.thread_id)
  end

  def test_body_of_iso_2022_jp_mail
    record = index("id1", raw_mail(content_type: "text/plain; " +
                                                 "charset=ISO-2022-JP",
                                   body: "こんにちは".encode("ISO-2022-JP").b +
                                         "\r\n"))
    assert_equal("こんにちは\n", record.body)
  end

  def test_body_of_multipart_mail
    body = <<~EOF.gsub(/\n/, "\r\n")
      --b
      Content-Type: text/plain; charset=UTF-8

      first part
      --b
      Content-Type: multipart/alternative; boundary="c"

      --c
      Content-Type: text/plain; charset=UTF-8

      nested text
      --c
      Content-Type: text/html; charset=UTF-8

      <p>nested html</p>
      --c--
      --b
      Content-Type: application/octet-stream; name="data.bin"
      Content-Disposition: attachment; filename="data.bin"

      AAAA
      --b
      Content-Type: message/rfc822

      Subject: inner
      Content-Type: text/plain

      inner body
      --b--
    EOF
    record = index("id1", raw_mail(content_type: "multipart/mixed; " +
                                                 "boundary=\"b\"",
                                   body: body))
    assert_equal("first part\n\nnested text\n\n\ndata.bin\ninner body",
                 record.body)
  end

  def test_reindexing_is_a_no_op
    index("id1", raw_mail(subject: "first"))
    record = index("id1", raw_mail(subject: "second"))
    assert_equal("first", record.subject)
    assert_equal(1, Groonga["Messages"].size)
  end

  def test_search
    index("id1", raw_mail(subject: "Groonga release", body: "plain\r\n"))
    index("id2", raw_mail(subject: "unrelated", body: "about Groonga\r\n"))
    index("id3", raw_mail(subject: "unrelated", body: "nothing\r\n"))
    index("id4", raw_mail(subject: "日本語の件名", body: "本文です\r\n"))
    search = ->(query) {
      Groonga["Messages"].select { |record|
        record.match(query) { |match| match.subject | match.body }
      }.map(&:_key).sort
    }
    assert_equal(["id1", "id2"], search.call("groonga"))
    assert_equal(["id4"], search.call("件名"))
    assert_equal(["id4"], search.call("本文"))
    assert_equal([], search.call("missing"))
  end

  def test_delete
    index("id1", raw_mail)
    Groonga["Messages"].delete("id1")
    assert_nil(Groonga["Messages"]["id1"])
    assert_raise(Groonga::InvalidArgument) do
      Groonga["Messages"].delete("id1")
    end
  end
end
