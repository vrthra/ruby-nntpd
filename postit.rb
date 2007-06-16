require 'date'
date = DateTime.now().strftime(fmt='%a, %d %b %Y %T %z')
msgstr = <<END_OF_MESSAGE
From: Your Name <your@mail.address>
Newsgroups: news.hive.talk
Subject: test message
Date: #{date}

This is a test message.
END_OF_MESSAGE

require 'net/nntp'
Net::NNTP.start('akasham.indigo', 119) do |nntp|
    nntp.post msgstr
end
 
