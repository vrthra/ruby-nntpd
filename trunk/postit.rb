require 'date'
date = DateTime.now().strftime(fmt='%a, %d %b %Y %T %z')
msgstr = <<END_OF_MESSAGE
From: Your Name <your@mail.address>
Newsgroups: news.hive.talk, news.hive.run
Subject: test message
Date: #{date}

This is a test message.
END_OF_MESSAGE

require 'net/nntp'
begin
    puts "connect to  #{ARGV[0] || 119}"
    Net::NNTP.start('vayavyam.india.sun.com', ARGV[0] || 119 ) do |nntp|
        nntp.post msgstr
    end
rescue Exception => e
    puts e.message
end
 
