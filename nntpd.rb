#!/usr/local/bin/ruby
require 'webrick'
require 'thread'
require 'nntpreplies'
require 'netutils'
require 'db'

#   ARTICLE BODY GROUP HEAD HELP IHAVE LAST LIST NEWGROUPS NEWNEWS NEXT POST QUIT SLAVE STAT XOVER

include NNTPReplies

module NNTPD
    class NNTPClient
        include NetUtils
        attr_accessor :db

        def initialize(sock, serv, db)
            @serv = serv
            @socket = sock
            @db = db
            @current_article_id = 1
        end

        def closed?
            return @socket.nil? || @socket.closed?
        end
        
        def handle_group(param)
            @current_group = db[param]
            if @current_group
                reply :numeric, RPL_GSELECT, @current_group.status + ' group selected'
            else
                reply :numeric, ERR_NOSUCHGROUP, ' no such group'
            end
        end

        def handle_list()
            reply :numeric, RPL_GLIST, 'list of news groups follows'
            db.groups.each do |n,g|
                reply :raw, g.summary
            end
            reply :done
        end

        def handle_xover(range)
            return reply(:numeric, ERR_NOGROUPSELECTED, 'no group selected') if !@current_group
            range = @current_article_id if !range
            reply :numeric, RPL_ALIST, 'list of article numbers follows'
            articles = @current_group[range]
            articles.keys.sort.each do |aid|
                reply :raw, aid.to_s + "\t" + articles[aid].overview
            end
            reply :done
        end

        def handle_post
            begin
                reply :numeric, RPL_SENDPOST, 'send the post, end with .'
                buf = []
                while ((s = @socket.gets.strip) !~ /^\.$/)
                    buf << s
                end
                db.write(buf)
                reply :numeric, RPL_POSTOK, 'post completed.'
            rescue Exception => e
                reply :numeric, ERR_NOSUCHGROUP, " error: #{e.message}."
                puts e.message
                puts e.backtrace
            end
        end

        # does not handle <msgid> yet
        def handle_article(num)
            return reply( :numeric, ERR_NOSUCHARTICLE, "no such article found") if !@current_group
            @current_article_id = num.to_i if num
            article = @current_group[@current_article_id.to_s].values[0]
            if article
                reply :numeric, RPL_ARTICLE, "#{num} #{article.msgid} article retrieved - head and body follow"
                reply :raw, article.to_s
                reply :done
            else
                reply :numeric, ERR_NOSUCHARTICLE, "no such article found"
            end
        end

        # does not handle <msgid> yet
        def handle_stat(num)
            return reply( :numeric, ERR_NOSUCHARTICLE, "no such article found") if !@current_group
            @current_article_id = num.to_i if num
            article = @current_group[@current_article_id.to_s].values[0]
            if article
                reply :numeric, RPL_STAT, "#{num} #{article.msgid} article retrieved"
                reply :raw, article
                reply :done
            else
                reply :numeric, ERR_NOSUCHARTICLE, "no such article found"
            end
        end

        def handle_newgroups(date,time,gmt,dist)
            reply :numeric, RPL_NEWGROUPS, " list of new newsgroups follows"
            #TODO:
            reply :done
        end

        def handle_newnews(newsgroups,date,time,gmt,dist)
            reply :numeric, RPL_NEWNEWS, " list of new newsgroups follows"
            #TODO:
            reply :done
        end

        def handle_mode(article)
            # bogus but nntp.rb library needs it. so temporarily this is it.
            reply :numeric, RPL_STREAM , "bogus we dont support stream but every one sends it."
        end

        def handle_quit()
            return if @dead
            @dead = true
            reply :numeric, RPL_QUIT, "Good bye"
            @socket.close if !@socket.closed?
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
                @socket.print arg.strip + "\n" if !arg.nil?
            rescue Exception => e
                carp e
                handle_abort()
                raise e if abrt
            end
        end
    end

    class NNTPServer < WEBrick::GenericServer
        include NetUtils

        def run(sock)
            client = NNTPClient.new(sock, self, @db)
            client.handle_connect
            nntp_listen(sock, client)
        end

        def nntp_listen(sock, client)
            begin
                while !sock.closed? && !sock.eof?
                    s = sock.gets
                    handle_client_input(s.strip, client)
                end
            rescue Exception => e
                carp e
            end
            client.handle_abort()
        end

        def db(d)
            @db = d
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
            when /^NEWGROUPS +(\d{6}) +(\d{6})( +GMT)?( +.*)?$/i
                client.handle_newgroups($1, $2, $3, $4)
            when /^NEWNEWS ([^\s]+) +(\d{6}) +(\d{6})( +GMT)?( +.*)?$/i
                client.handle_newnews($1, $2, $3, $4, $5)

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
            when /^EVAL (.*)$/i
                #strictly for debug
                client.handle_eval($1)
            else
                client.handle_unknown(s)
            end
        end
    end
end

if __FILE__ == $0
    $config ||= {}
    $config['version'] = '0.01dev'
    $config['port'] = 1119
    $verbose = ARGV.shift || false

    s = NNTPD::NNTPServer.new( :Port => $config['port'] )
    db = NNTPD::DB.load('/tmp/ruby-nntpd')
    s.db(db)

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

