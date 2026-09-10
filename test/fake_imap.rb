require "net/imap"

# A stand-in for Net::IMAP that serves messages from a Hash and records
# every call.  Methods the plugin does not use are left undefined so that
# a new IMAP command fails loudly here instead of silently succeeding.
class FakeIMAP
  Message = Struct.new(:envelope, :flags, :body, keyword_init: true)

  attr_reader :calls, :responses, :messages, :mailboxes
  attr_accessor :store_returns_nil

  def initialize(uidvalidity: 1)
    @messages = {}
    @responses = { "UIDVALIDITY" => [uidvalidity] }
    @calls = []
    @mailboxes = ["INBOX"]
    @store_returns_nil = false
  end

  def self.address(name, mailbox, host = "example.com")
    Net::IMAP::Address.new(name, nil, mailbox, host)
  end

  def add_message(uid, from: [FakeIMAP.address("Alice", "alice")],
                  subject: "hello",
                  date: "Mon, 1 Sep 2025 10:00:00 +0000",
                  message_id: "<#{uid}@example.com>", in_reply_to: nil,
                  flags: [], body: nil)
    envelope = Net::IMAP::Envelope.new(date, subject, from, from, from,
                                       nil, nil, nil, in_reply_to,
                                       message_id)
    @messages[uid] = Message.new(envelope: envelope, flags: flags,
                                 body: body)
    self
  end

  def disconnected?
    false
  end

  def select(mailbox)
    record(:select, mailbox)
    @selected = mailbox
  end

  def uid_search(criteria)
    record(:uid_search, criteria)
    @messages.keys.sort
  end

  def uid_fetch(set, attr)
    record(:uid_fetch, set, attr)
    names = Array(attr)
    Array(set).filter_map { |uid|
      message = @messages[uid]
      next if message.nil?
      data = { "UID" => uid }
      data["ENVELOPE"] = message.envelope if names.include?("ENVELOPE")
      data["FLAGS"] = message.flags if names.include?("FLAGS")
      data["BODY[]"] = message.body if names.include?("BODY[]")
      Net::IMAP::FetchData.new(uid, data)
    }
  end

  def uid_store(set, attr, flags)
    record(:uid_store, set, attr, flags)
    Array(set).map { |uid|
      message = @messages.fetch(uid)
      case attr
      when "+FLAGS"
        message.flags |= flags
      when "-FLAGS"
        message.flags -= flags
      else
        raise ArgumentError, "unsupported attr: #{attr}"
      end
      Net::IMAP::FetchData.new(uid, { "UID" => uid,
                                      "FLAGS" => message.flags })
    }.then { |data| @store_returns_nil ? nil : data }
  end

  def list(refname, mailbox)
    record(:list, refname, mailbox)
    @mailboxes.include?(mailbox) ? [mailbox] : nil
  end

  def create(mailbox)
    record(:create, mailbox)
    @mailboxes.push(mailbox)
  end

  def uid_copy(set, mailbox)
    record(:uid_copy, set, mailbox)
  end

  def expunge
    record(:expunge)
    @messages.delete_if { |uid, message| message.flags.include?(:Deleted) }
  end

  def append(mailbox, message, flags = nil, date_time = nil)
    record(:append, mailbox, message, flags)
  end

  def noop
    record(:noop)
  end

  def calls_of(name)
    @calls.select { |call| call.first == name }
  end

  private

  def record(*call)
    @calls.push(call)
  end
end
