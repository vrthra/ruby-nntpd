require 'thread'
module NNTPD
    # representation of an article.
    # Used to parse an article that was posted or to load an article that was
    # stored to disk.

    class Article
        def initialize(headers, body)
            @headers = headers
            @body = body
            #anum   subject  from   date   <msgid>   <ref>   size  lines
            @format = [:subject, :from, :date, :'message-id', :reference, :size, :lines]
        end

        def Article.parse(lines, update_msgid=false)
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
            if update_msgid
                headers[:'message-id'] = DB.guid
            end
            return Article.new(headers, body)
        end

        def []=(name, value)
            @all = @overview = nil
            @headers[name.downcase.intern] = value
        end

        def newsgroups
            return (@newsgroups ||= @headers[:newsgroups].split(/\s*,\s*/))
        end

        def msgid
            return @headers[:'message-id']
        end

        def [](var)
            case var
            when :size
                return (@size ||= to_s.length)
            when :lines
                return (@lines ||= @body.length + @headers.keys.length + 1)
            when :body
                return @body
            else
                return @headers[var] || ' '
            end
        end

        def overview
            return (@overview ||= @format.collect {|fmt| self[fmt]}).join("\t")
        end

        def to_s
            return (@all ||= @headers.inject('') {|acc,kv|
                kv[0].to_s.capitalize + ': ' + kv[1] + "\r\n" + acc} + "\r\n" + @body.join("\r\n"))
        end
    end


    # synchronized
    class Group
        attr_reader :name

        def initialize(name)
            @name = name
            @articles = []
            @lock = Mutex.new
            @first = @last = 0
        end

        def Group.create(name)
            return Group.new(name)
        end

        # The group.parse comes into play when a message is posted to this
        # group. You can plug in custom parsers here.
        def Group.parse(file)
        end

        def Group.dump()
        end

        def << (article)
            @lock.synchronize { @articles << article }
        end

        def first
            @lock.synchronize { return @first + 1}
        end
        
        def last
            @lock.synchronize { return @first + @articles.length }
        end
        
        private :first ,:last

        def size
            @lock.synchronize { return @articles.length}
        end

        def [](range)
            #range may be [nil | NNN | NNN- | NNN-MMM]
            @lock.synchronize {
                first = @first
                last = @last
                case range.strip
                when /^([\d]+)$/
                    num = $1.strip.to_i
                    return num && @articles[num - 1] ? [@articles[num - 1]] : []
                when /^([\d]+)-$/
                    first = $1.strip.to_i
                when /^([\d]+)-([\d]+)$/
                    first = $1.strip.to_i
                    last = $2.strip.to_i
                end
                return @articles[first-1 .. last-1]
            }
        end

        #numarticles firstarticle lastarticle nameofgroup
        def status
            return size > 0 ? "#{size} #{first} #{last} #{name}" : "0 0 0 #{name}"
        end

        # group last first postallowed
        def summary
            return size > 0 ?  "#{name} #{last} #{first} #{canpost}" : "#{name} 0 0 y"
        end

        def canpost
            return 'y'
        end
    end

    class DB
        def DB.create(location=nil)
            return DB.new()
        end
        def DB.guid
            return "<#{Time.now.to_f}@#{Socket.gethostname}>"
        end
        def initialize
            @db = {}
        end
        def []=(name, group)
            @db[name.intern] = group
        end
        def [](name)
            return @db[name.intern]
        end
        def groups
            return @db
        end
    end
end


