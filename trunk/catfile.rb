require 'db'
module NNTPD

    class PatLogCache
        @@lock = Mutex.new
        @@cache = {}
        def PatLogCache.getpath(article)
            ai = article.to_i
            @@lock.synchronize {
                @@cache.keys.each {|k| return k, @@cache[k] if k.include?(ai) }
            }
        end

        def PatLogCache.get(article)
            range, path = PatLogCache.getpath(article)
            lines = File.open(path).readlines
            r = CatArticle.parselog(lines)
            p range
            p range.first 
            p article
            tc = r[article.to_i - range.first]
            h,hdr,body,lines,size = CatArticle.get_tc_content(tc)
            return hdr + body.join("\r\n")
        end

        def PatLogCache.register(range, file)
            @@lock.synchronize { @@cache[range] = file }
        end
    end
    class CatArticle
        attr_reader :size, :lines, :newsgroups
        def initialize(headers, size, lines)
            @newsgroups = headers[:newsgroups].split(/\s*,\s*/)
            @size = size
            @lines = lines
            #anum   subject  from   date   <msgid>   <ref>   size  lines
            @format = [:subject, :from, :date, :'message-id', :reference, :size, :lines]
            @headers = headers.reject{|k,v| !@format.include?(k)}
        end
        def CatArticle.parsebuf(buf)
            tcases = []
            c = {}
            summary = []
            fails = 0
            buf.each do |s|
                case s 
                when /^\>(.*)/
                    c = {}
                    c[:subject] = $1
                    c[:body] = [s]
                    tcases << c
                when /^CTE /
                    summary << s
                    tcases << c if c
                    c = nil
                when /^stat : \(([0-9]+)\/[0-9]+\)/
                    c[:status] = (fails == $1.strip.to_i)
                    fails = $1.strip.to_i
                    c[:body] << s
                else
                    c[:body] << s if c && c[:body]
                end
            end
            return tcases, summary, fails
        end

        def CatArticle.parselog(lines, update_msgid=false)
            head = true
            headers = {}
            body = []
            prev = ''
            lines.each do |line|
                case line.strip
                when /^$/
                    head = false
                when head && /^([^\s:]+)\s*:\s*(.+)$/
                    headers[prev = $1.downcase.intern] = $2.strip
                when head
                    headers[prev] += ' ' + line.strip # continuing headers
                else
                    body << line
                end
            end
            headers[:'message-id'] = DB.guid if update_msgid
            tcases,summary,fails = CatArticle.parsebuf(body)
            # creat summary header and body first
            headers[:subject] = "cat summary #{fails} failed"
            sum = {}
            sum[:headers] = headers
            sum[:body] = summary

            r = [sum]
            #do the same for each cases
            (0..(tcases.length - 1)).each do |i|
                t = tcases[i]
                h = {}
                headers.each {|k,v| h[k] = v} # make a copy
                h[:'message-id'] = headers[:'message-id'].sub(/\./,".#{i.to_s}.")
                h[:reference] = headers[:'message-id']
                h[:subject] = t[:subject] + " #{t[:status]? 'passed' : 'failed'}"
                r << {:headers => h, :body => t[:body]}
            end
            return r
        end

        def CatArticle.get_tc_content(tc)
            headers = tc[:headers]
            body = tc[:body]
            b = body.join("\r\n")
            hdr = headers.inject('') {|acc,kv| kv[0].to_s.capitalize + ': ' + kv[1] + "\r\n" + acc} + "\r\n"
            lines = headers.size + body.length + 1
            size = hdr.length + b.length
            return headers,hdr,body,lines,size
        end

        def CatArticle.parse(lines, update_msgid=false)
            r = CatArticle.parselog(lines,update_msgid)
            return r.collect{|tc|
                h,hdr,body,lines,size = get_tc_content(tc)
                CatArticle.new(h,size,lines)
            }
        end

        def [](var)
            case var
            when :size
                return @size
            when :lines
                return @lines
            else
                return @headers[var] || ' '
            end
        end

        def overview
            return (@overview ||= @format.collect {|fmt| self[fmt]}).join("\t")
        end
        def msgid
            return @headers[:'message-id']
        end

        # we should do the caching here.
        def getarticle(path)
            aid = File.basename(path)
            return PatLogCache.get(aid)
        end

        def writearticle(path, buf)
        end
    end

    class ParseCat
        attr_reader :name,:first,:last,:size
        def initialize(name,path,config)
            @name = name
            @articles = {}
            @lock = Mutex.new
            @first = @last = 0
            @config = config
            @path = path
            @startid = 0
            # iterate throu path, registering each article we find
            print "Loading cat #{@name} #{path}"
            Dir.mkdir path rescue puts "+"
            Dir[path + '/*'].each do |afile|
                @startid = File.basename(afile).to_i
                puts "\tarticle #{afile}"
                begin
                    articles = CatArticle.parse(File.open(afile).readlines)
                    print "."
                    articles.each do |article|
                        register(@startid.to_s,article) # keeps only the overview information
                        @startid+=1
                    end
                    PatLogCache.register((File.basename(afile).to_i .. @startid), afile)
                rescue Exception => e
                    puts "Invalid article #{afile}"
                    puts e.message
                    puts e.backtrace
                end
            end
            puts ""
            @size = @startid
            @last = @size
        end

        def register(aid,article)
            @lock.synchronize { @articles[aid] = ArticleHolder.new(article, @path + '/' + aid) }
        end
        
        def [](range)
            #range may be [nil | NNN | NNN- | NNN-MMM]
            @lock.synchronize {
                first = @first
                last = @last
                case range.strip
                when /^([\d]+)$/
                    num = $1.strip.to_i
                    return @articles.reject{|k,v| k.to_i != num}
                when /^([\d]+)-$/
                    first = $1.strip.to_i
                    return @articles.reject {|k,v| k.to_i < first}
                when /^([\d]+)-([\d]+)$/
                    first = $1.strip.to_i
                    last = $2.strip.to_i
                    return @articles.reject {|k,v| k.to_i < first || k.to_i > last}
                else
                    raise "invalid range"
                end
            }
        end

        def <<(article)
            puts "In parsecat."
            add(article)
        end
        def status
            return size > 0 ? "#{size} #{first} #{last} #{name}" : "0 0 0 #{name}"
        end

        # group last first postallowed
        def summary
            return size > 0 ?  "#{name} #{last} #{first} n" : "#{name} 0 0 n"
        end
    end

end

