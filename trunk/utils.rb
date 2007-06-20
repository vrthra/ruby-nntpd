module NNTPD
    class Util
        # splits into headers{} and body[]
        def Util.parse_msg(lines)
            head = true
            headers = {}
            body = []
            prev = ''
            lines.each do |line|
                case line.strip
                when /^$/
                    head = false
                    body << line
                when head && /^([^\s:]+)\s*:\s*(.+)$/
                    headers[prev = $1.downcase.intern] = $2.strip
                when head
                    headers[prev] += ' ' + line.strip # continuing headers
                else
                    body << line
                end
            end
            return headers,body
        end

        def Util.get_tc_content(tc)
            headers = tc[:headers]
            body = tc[:body]
            hdr = Util.get_headers_content(headers)
            bdy = body.join("")
            lines = headers.size + body.length
            size = hdr.length + bdy.length
            return hdr,bdy,lines,size
        end

        def Util.get_headers_content(headers)
            return headers.inject('') {|acc,kv|
                kv[0].to_s.capitalize + ': ' + kv[1] + "\r\n" + acc}
        end

        def Util.get_content(headers,body)
            return Util.get_headers_content(headers) + body.join("")
        end
    end

    class LogCache
        @@lock = Mutex.new
        @@cache = {}
        def LogCache.getpath(aid)
            @@lock.synchronize {
                @@cache.keys.each {|k| return k, @@cache[k] if k.include?(aid) }
            }
        end

        def LogCache.get(aid, parser)
            range, path = LogCache.getpath(aid)
            r = ParsedLog.splitlog(File.open(path).readlines, parser)
            tc = r[aid - range.first] # r is zero indexed.
            return Util.get_content(tc[:headers], tc[:body])
        end

        def LogCache.register(range, file)
            @@lock.synchronize { @@cache[range] = file }
        end
    end

    class BaseArticle
        attr_reader :headers, :newsgroups
        def format
            return [:subject, :from, :date, :'message-id', :reference, :size, :lines]
        end
        def [](var)
            case var
            when :size
                return @size
            when :lines
                return @lines
            else
                return headers[var] || ' '
            end
        end

        def initialize(h, size, lines)
            @headers = h.reject{|k,v| !format.include?(k)}
            @newsgroups = h[:newsgroups].split(/\s*,\s*/)
            @size = size
            @lines = lines
        end

        def overview
            return (@overview ||= format.collect {|fmt| self[fmt]}).join("\t")
        end
        
        def msgid
            return headers[:'message-id']
        end

        # override these in custom articles.
        def getarticle(aid,path)
            return File.open(path + '/' + aid.to_s).read
        end
        def writearticle(aid,buf,path)
            File.open(path + '/' + aid.to_s,'w+') {|f| f.print buf }
        end
    end

    class ArticleHolder
        def initialize(aid, article, path)
            @article = article
            @aid = aid
            @path = path
        end
        def to_s
            return @article.getarticle(@aid, @path)
        end
        def dump(buf)
            return @article.writearticle(@aid,buf,@path)
        end
        def method_missing(m,*args)
            @article.send(m,*args)
        end
    end

    class Elem
        attr_reader :subject, :body
        attr_writer :subject
        def initialize
            @subject = ''
            @body = []
        end
        def <<(str)
            @body << str
        end
    end

    class ParsedLog
        def ParsedLog.splitlog(lines, parser)
            headers,body = Util.parse_msg(lines)
            # we get a common message id when Article.parse is run on the whole log on posting.
            tcases,summary= parser.parse(body)
            # create summary header and body first
            headers[:subject] = summary.subject
            r = [{:headers => headers, :body => summary.body}]
            #do the same for each cases
            (0..(tcases.length - 1)).each do |i|
                t = tcases[i]
                h = headers.dup.update({
                    :'message-id' => headers[:'message-id'].sub(/\./,".#{i.to_s}."),
                    :reference => headers[:'message-id'],
                    :subject => t.subject
                })
                r << {:headers => h, :body => t.body}
            end
            return r
        end
    end

    class BaseGroup
        attr_reader :name
        def initialize(name,path,config)
            @name = name
            @articles = {}
            @lock = Mutex.new
            @first = @last = 0
            @path = path
            @config = config
        end

        def status
            @lock.synchronize {return "#{@articles.size} #{@first} #{@last} #{@name}"}
        end

        # group last first postallowed
        def summary
            @lock.synchronize {return "#{@name} #{@last} #{@first} #{canpost}"}
        end

        def canpost
            return 'n'
        end

        def [](range)
            #range may be [nil | NNN | NNN- | NNN-MMM]
            @lock.synchronize {
                case range.strip
                when /^([\d]+)$/
                    num = $1.strip.to_i
                    return {num => @articles[num]}
                when /^([\d]+)-$/
                    f = $1.strip.to_i
                    return @articles.reject {|k,v| k < f}
                when /^([\d]+)-([\d]+)$/
                    f = $1.strip.to_i
                    l = $2.strip.to_i
                    return @articles.reject {|k,v| k < f || k > l}
                else
                    # ignore.
                end
            }
        end

        def add(aid,article)
                # if we dont have first yet, update it.
                @first ||= aid
                #this is our last article.
                @last = aid
                return (@articles[@last] = ArticleHolder.new(@last,article,@path))
        end
        private :add

        def []=(aid,article)
            @lock.synchronize {add(aid,article)}
        end

        def <<(arr)
            article = arr[0]
            buf = arr[1]
            @lock.synchronize {add(@last + 1, article).dump(buf)}
        end

    end

    class LogArticle < BaseArticle
        def initialize(h, size, lines, parser)
            super(h,size,lines)
            @parser = parser
        end

        def LogArticle.parse(lines, parser)
            r = ParsedLog.splitlog(lines, parser)
            return r.collect{|tc|
                hdr,bdy,lines,size = Util.get_tc_content(tc)
                LogArticle.new(tc[:headers] ,size, lines, parser)
            }
        end

        # we should do the caching here. 
        # return the article txt after fetching it from the disk
        def getarticle(aid,path)
            return LogCache.get(aid, @parser)
        end

        def writearticle(aid,buf,path)
            # dummy. it will be done by the group rather than us.
        end
    end
end

