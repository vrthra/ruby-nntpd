#!/usr/local/bin/ruby
require 'webrick'
require 'thread'
require 'nntpreplies'
require 'netutils'

#   ARTICLE
#   BODY
#   GROUP
#   HEAD
#   HELP
#   IHAVE
#   LAST
#   LIST
#   NEWGROUPS
#   NEWNEWS
#   NEXT
#   POST
#   QUIT
#   SLAVE
#   STAT
#
#   XOVER

include NNTPReplies

$config ||= {}
$config['version'] = '0.01dev'
$config['port'] = 1119
$config['hostname'] = Socket.gethostname.split(/\./).shift

$verbose = ARGV.shift || false

class Article
    def initialize(headers, all)
        @i = headers
        @all = all
        @i[:lines] = all.length
        @i[:size] = 100
    end

    #OVERVIEW.FMT
    #anum   subject  from   date   <msgid>   <ref>   size  lines
    def summary
        return "#{@i[:subject]}\t#{@i[:from]}\t#{@i[:date]}\t#{@i[:msgid]}\t#{@i[:ref]}\t#{@i[:size]}\t#{@i[:lines]}"
    end

    def all
        return "Message-id: " + @i[:msgid] + '\r\n' + @all.join('')
    end
end

class Group
    def initialize(name)
        @name = name
        @articles = []
    end

    def name
        return @name
    end

    def add(headers,arr)
        @articles << Article.new(headers, arr)
    end

    def articles(range)
        #range may be [nil | NNN | NNN- | NNN-MMM]
        case range
        when /^([0-9]+)-$/
            return @articles[$1.strip.to_i - 1 .. -1]
        when /^([0-9]+)-([0-9]+)$/
            return @articles[$1.strip.to_i - 1 .. $2.strip.to_i]
        end
    end

    def [](num)
        return nil if num == 0
        return @articles[num.to_i - 1]
    end

    def first_article
        return 0 if @articles.length == 0
        return 1
    end

    def last_article
        return 0 if @articles.length == 0
        return @articles.length
    end

    #numarticles firstarticle lastarticle nameofgroup
    def description
        return "#{@articles.length} #{first_article} #{last_article} #{name}"
    end
    
    # group last first postallowed
    def summary
        return "#{name} #{last_article} #{first_article} #{canpost}"
    end

    def canpost
        return true
    end
end

$db = {}

class DB
    def DB.groups
        return $db
    end
    def DB.group(var)
        return $db[var]
    end
end

$msg_id_seq = 1
def get_msgid()
    id = '<' + $msg_id_seq.to_s + '.100@' + $config['hostname'] + '.sun.com>'
    $msg_id_seq += 1
    return id
end

#From: hive@agneyam.sun.com
#Newsgroups: news.cat.run
#Subject: summary: 3 failed.
#Message-id: <100.10@hive.net>
#Date: Fri, 19 Nov 82 16:14:55 GMT
#Reference: <99.1@hive.net>
#Followup-To: news.cat.run
#Expires: Sat, 1 Jan 83 00:00:00 -0500

def get_newsgroups(str)
    return str.split(/ +/)
end

def process_article(arr)
    head = true
    headers = {}
    body = []
    arr.each do |line|
        if line =~ /^$/
            head = false
        end
        if head
            #"#{@i[:subject]}\t#{@i[:from]}\t{@i[:date]}\t#{@i[:msgid]}\t#{@i[:ref]}\t#{@i[:size]}\t#{@i[:lines]}"
            case line.strip
            when /^From *:(.+)$/i
                headers[:from] = $1.strip
            when /^Newsgroups *:(.+)$/i
                headers[:newsgroups] = $1.strip
            when /^Subject *:(.+)$/i
                headers[:subject] = $1.strip
            when /^Date *:(.+)$/i
                headers[:date] = $1.strip
            when /^References *:(.+)$/i
                headers[:ref] = $1.strip
            when /^Message-id *:(.+)$/i
                #loose it.
            when /^([^ :]+) *:(.+)$/
                headers[$1.strip] = headers[$2.strip]
            end
        else
            body << line
        end
    end
    headers[:msgid] = get_msgid()
    get_newsgroups(headers[:newsgroups]).each do |gname|
        DB.group(gname).add(headers, arr)
    end
end


class NNTPClient
    include NetUtils

    attr_reader :state

    def initialize(sock, serv)
        @serv = serv
        @socket = sock
        @peername = peer()

        # for maintaining the article pointer
        @state = {} 
        @current_article_id = 1

        carp "initializing connection from #{@peername}"
    end

    def closed?
        return @socket.nil? || @socket.closed?
    end

    def peer
        begin
            sockaddr = @socket.getpeername
            begin
                return Socket.getnameinfo(sockaddr, Socket::NI_NAMEREQD).first
            rescue
                return Socket.getnameinfo(sockaddr).first
            end
        rescue
            return @socket.peeraddr[2]
        end
    end

    def handle_group(param)
        @current_group = DB.group(param)
        @current_article_id = 1
        if @current_group
            reply :numeric, RPL_GSELECT, @current_group.description + ' group selected'
        else
            reply :numeric, ERR_NOSUCHGROUP, ' no such group'
        end
    end

    def handle_list()
        reply :numeric, RPL_GLIST, 'list of news groups follows'
        DB.groups.each do |n,g|
            reply :raw, g.summary
        end
        reply :done
    end

    def handle_xover(range)
        reply :numeric, RPL_ALIST, 'list of article numbers follows'
        if !range
            reply :raw, @current_group[@current_article_id].summary
            reply :done
        else
            if range =~ /^[^-]+$/
                article = @current_group[range]
                if article
                    reply :raw, article.summary
                else
                    reply :numeric, ERR_NOSUCHARTICLE, 'no such aritcle'
                end
            else
                anum = 1
                @current_group.articles(range).each do |article|
                    reply :raw, anum.to_s + ' ' + article.summary
                    anum += 1
                end
                reply :done
            end
        end
    end
    
    def handle_post
        reply :numeric, RPL_SENDPOST, 'send the post, end with .'
        buf = []
        while s = @socket.gets
            break if s.strip =~ /^\.$/
            buf << s
        end
        reply :numeric, RPL_POSTOK, ' post completed.'
        process_article(buf)
    end

    def handle_article(num)
        if !num
            num = @current_article
        end
        article = @current_group[num.to_i]
        reply :numeric, RPL_ARTICLE, num.to_s + ' '+ article.msgid + ' article retrieved - head and body follow'
        reply :raw, article.all
        reply :done
    end

    def handle_newgroups(one,two,three)
        raise "Not Impl"
    end

    def handle_mode(article)
        # bogus but nntp.rb library needs it. so temporarily this is it.
        reply :numeric, RPL_PWELCOME, "#{$config['version']} initialized, welcome."
    end

    def handle_stat(article)
        if !article
            if !@current_newsgroup
                repl_nonewsgroup
            else
                if !@current_article
                    repl_noarticle
                else
                    repl_statok
                end
            end
        end
    end

    def handle_quit()
        return if @dead
        @dead = true
        reply :numeric, RPL_QUIT, "Good bye"
        @socket.close if !@socket.closed?
    end

    def handle_reload(password)
    end

    def handle_abort()
        handle_quit
    end

    def handle_eval(s)
        reply :raw, eval(s)
    end

    def handle_unknown(s)
        reply :numeric, ERR_UNKNOWNCOMMAND,s, "Unknown command"
    end

    def handle_connect
        reply :numeric, RPL_PWELCOME, "#{$config['version']} initialized, welcome."
    end

    def reply(method, *args)
        case method
        when :done
            raw '.'
        when :raw
            arg = *args
            raw arg
        when :numeric
            numeric,msg = args
            raw "#{'%03d'%numeric} #{msg}"
        end
    end

    def raw(arg, abrt=false)
        begin
        carp "--> #{arg}"
        @socket.print arg.chomp + "\n" if !arg.nil?
        rescue Exception => e
            carp "<#{e.message}"
            puts e.backtrace.join("\n")
            handle_abort()
            raise e if abrt
        end
    end
end

class NNTPServer < WEBrick::GenericServer
    include NetUtils

    def run(sock)
        client = NNTPClient.new(sock, self)
        client.handle_connect
        nntp_listen(sock, client)
    end

    def hostname
        begin
            sockaddr = @socket.getsockname
            begin
                return Socket.getnameinfo(sockaddr, Socket::NI_NAMEREQD).first
            rescue
                return Socket.getnameinfo(sockaddr).first
            end
        rescue
            return @socket.peeraddr[2]
        end
    end

    def nntp_listen(sock, client)
        begin
            while !sock.closed? && !sock.eof?
                s = sock.gets
                handle_client_input(s.chomp, client)
            end
        rescue Exception => e
            carp e
        end
        client.handle_abort()
    end

    def handle_client_input(input, client)
        carp "<-- #{input}"
        s = input
        case s
        when /^[ ]*$/
            return
        when /^MODE +(.+)$/i
            client.handle_mode($1.strip)
        when /^STAT +(.+)$/i
            client.handle_stat($1.strip)
        when /^STAT */i
            client.handle_stat(nil)
        when /^LIST *$/i
            client.handle_list
        when /^GROUP +(.+)$/i
            client.handle_group($1)
        when /^NEWGROUPS +([^ ]+) +(.+) *(.*)$/i
            client.handle_newgroups($1, $2, $3)
        
        when /^XOVER *$/i
            client.handle_xover(nil)
        when /^XOVER +(.+)$/i
            client.handle_xover($1)

        when /^ARTICLE \<+(.+)\> *$/i
            client.handle_unknown($1) # not impl yet TODO:
        when /^ARTICLE +(.+)$/i
            client.handle_article($1)
        when /^ARTICLE *$/i #current article
            client.handle_article(nil)

        when /^POST *$/
            client.handle_post

        when /^QUIT *$/i
            client.handle_quit
        when /^RELOAD +(.+)$/i
            client.handle_reload($1)
        when /^EVAL (.*)$/i
            #strictly for debug
            client.handle_eval($1)
        else
            client.handle_unknown(s)
        end
    end
end


if __FILE__ == $0
    $db['news.cat.run'] = Group.new('news.cat.run')
    $db['news.hive.run'] = Group.new('news.hive.run')
    $db['news.hive.talk'] = Group.new('news.hive.talk')

    #require 'nntpclient'
    s = NNTPServer.new( :Port => $config['port'] )
    begin
        while arg = ARGV.shift
            case arg
            when /-v/
                $verbose = true
            end
        end
        trap("INT"){
            s.carp "killing #{$$}"
            system("kill -9 #{$$}")
            s.shutdown
        }
        s.start
    rescue Exception => e
        s.carp e
    end
end

