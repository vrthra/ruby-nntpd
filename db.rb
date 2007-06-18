require 'thread'
require 'yaml'
require 'catfile'
module NNTPD
    # representation of an article.
    # Used to parse an article that was posted or to load an article that was
    # stored to disk.

    class Article
        def initialize(headers, size, lines)
            @newsgroups = headers[:newsgroups].split(/\s*,\s*/)
            @size = size
            #anum   subject  from   date   <msgid>   <ref>   size  lines
            @format = [:subject, :from, :date, :'message-id', :reference, :size, :lines]
            @headers = headers.reject{|k,v| !@format.include?(k)}
            @lines = lines
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
            headers[:'message-id'] = DB.guid if update_msgid
            str = (headers.inject('') {|acc,kv|
                kv[0].to_s.capitalize + ': ' + kv[1] + "\r\n" + acc} + "\r\n" + body.join("\r\n"))
            lines = body.length + headers.keys.length + 1
            return Article.new(headers, str.length, lines), str
        end

        def newsgroups
            return @newsgroups
        end

        def msgid
            return @headers[:'message-id']
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

        # each article type is responsible for reading and writing its own type.
        def getarticle(path)
            return File.open(path).read
        end
        
        def writearticle(path, buf)
            File.open(path,'w+') {|f|
                f.print buf
            }
        end
    end

    class ArticleHolder
        def initialize(article, path)
            @article = article
            @path = path
        end
        def to_s
            return @article.getarticle(@path)
        end
        def dump(buf)
            return @article.writearticle(@path,buf)
        end
        def method_missing(m,*args)
            @article.send(m,*args)
        end
    end


    # synchronized
    class Group
        attr_reader :name

        def initialize(name,path,config)
            # config : name description creation date
            @name = name
            @articles = {}
            @lock = Mutex.new
            @first = @last = 0
            @config = config
            @path = path
            # iterate throu path, registering each article we find
            print "Loading group #{@name} #{path}"
            Dir.mkdir path rescue puts "+"
            Dir[path + '/*'].each do |afile|
                begin
                    article,str = Article.parse(File.open(afile).readlines)
                    print "."
                    register(File.basename(afile),article) # keeps only the overview information
                rescue
                    puts "Invalid article #{afile}"
                end
            end
            puts ""
        end

        def Group.load(name,path,config)
            gklass = eval(config[:loader] || 'Group')
            return gklass.new(name,path,config)
        end

        def register(aid,article)
            @lock.synchronize { @articles[aid] = ArticleHolder.new(article, @path + '/' + aid) }
        end

        def push(article,buf)
            add(article,buf).dump(buf)
        end
        def add(article,buf)
            @lock.synchronize {
                aid = (@first + @articles.size + 1).to_s
                return  @articles[aid] = ArticleHolder.new(article, @path + '/' + aid)
            }
        end

        def first
            @lock.synchronize { return @first + 1}
        end
        
        def last
            @lock.synchronize { return @first + @articles.size }
        end
        
        private :first ,:last

        def size
            @lock.synchronize { return @articles.size}
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
        def DB.load(location=nil)
            return DB.new(location)
        end
        def DB.guid
            return "<#{Time.now.to_f}@#{Socket.gethostname}>"
        end
        def initialize(location)
            @db = {}
            # loadup the config.yaml which contains supported groups
            config = YAML::load_file(location + '/config.yaml')
            config.keys.each do |groupname|
                self[groupname] = Group.load(groupname,location + '/' + groupname, config[groupname])
            end
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

        def write(buf)
            article,str = Article.parse(buf, true)
            article.newsgroups.each do |gname|
                if self[gname]
                    self[gname].push(article,str)
                else
                    raise 'No such news group'
                end
            end
        end
    end
end


