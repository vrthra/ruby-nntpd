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
        @article,@str = NNTPD::Article.parse(MSGTEXT.split("\n"))
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

end
