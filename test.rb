require 'test/unit'
require 'db'
MSGTEXT =<<EOF
Message-ID: <123@vayavyam>
From: Your Name <your@mail.address>
Newsgroups: news.hive.talk, news.hive.run
Subject: message
Date: Sun, 17 Jun 2007 01:28:44

A line
next.
EOF

class TestArticle < Test::Unit::TestCase
    def setup
        @article = NNTPD::Article.parse(MSGTEXT.split("\n"))
    end

    def test_newsgroups
        assert_equal ['news.hive.talk', 'news.hive.run'],
                     @article.newsgroups
    end

    def test_arr
        assert_equal 174,
                     @article[:size]
        assert_equal 8,
                     @article[:lines]
    end

    def test_overview
        assert_equal "message\tYour Name <your@mail.address>\tSun, 17 Jun 2007 01:28:44\t<123@vayavyam>\t \t174\t8",
                     @article.overview
    end
    def test_tos
        assert_equal ["", "A line", "Date: Sun, 17 Jun 2007 01:28:44", "From: Your Name <your@mail.address>",
                     "Message-id: <123@vayavyam>", "Newsgroups: news.hive.talk, news.hive.run", "Subject: message", "next."],
                     @article.to_s.split(/\r\n/).sort
    end

    class TestGroup < Test::Unit::TestCase
        def test_add
            group = NNTPD::Group.create('news.aboute.me')
            assert_equal 'news.aboute.me 0 0 y', group.summary
            group << NNTPD::Article.parse(MSGTEXT.split("\n"))
            assert_equal 'news.aboute.me 1 1 y', group.summary
            group << NNTPD::Article.parse(MSGTEXT.split("\n"))
            group << NNTPD::Article.parse(MSGTEXT.split("\n"))
            assert_equal 'news.aboute.me 3 1 y', group.summary
        end

        def test_range
            group = NNTPD::Group.create('news.aboute.you')
            assert_equal [],group['1'] # no such article
            group << NNTPD::Article.parse(MSGTEXT.split("\n"))
            article = group['1'][0]
            assert_equal 'message',article[:subject]
        end

        def test_status
            group = NNTPD::Group.create('news.aboute.him')
            assert_equal '0 0 0 news.aboute.him', group.status
            group << NNTPD::Article.parse(MSGTEXT.split("\n"))
            group << NNTPD::Article.parse(MSGTEXT.split("\n"))
            assert_equal '2 1 2 news.aboute.him', group.status
        end
    end
end
