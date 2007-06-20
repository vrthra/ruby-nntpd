require 'thread'
require 'yaml'
require 'utils'
require 'catfile'
module NNTPD
    # representation of an article.
    # Used to parse an article that was posted or to load an article that was
    # stored to disk.

    class Article < BaseArticle
        def initialize(h, size, lines)
            super(h,size,lines)
        end

        def Article.parse(lines, update_msgid=false)
            headers,body = Util.parse_msg(lines)

            headers.update({
                :'message-id' => DB.guid,
                :'date' => Time.now.gmtime.to_s
            }) if update_msgid
            str = Util.get_content(headers,body)
            lines = body.length + headers.keys.length + 1
            return Article.new(headers, str.length, lines), str
        end
    end

    # synchronized
    class Group < BaseGroup
        def initialize(name,path,config)
            super(name,path,config)
            # iterate throu path, registering each article we find
            print "Loading group #{@name} #{path}"
            Dir.mkdir path rescue puts "+"
            Dir[path + '/*'].each do |afile|
                begin
                    article,str = Article.parse(File.open(afile).readlines)
                    print "."
                    self[File.basename(afile).to_i] = article # keeps only the overview information
                rescue Exception => e
                    puts "Invalid article #{afile}"
                end
            end
            puts ""
        end

        def canpost
            return 'y'
        end
    end

    class DB
        def DB.load(location=nil)
            return DB.new(location)
        end

        def load_group(name,path,config)
            gklass = eval(config[:loader] || 'Group')
            return gklass.new(name,path,config)
        end

        def DB.guid
            return "<#{Time.now.to_f}@#{Socket.gethostname}>"
        end

        def initialize(location)
            @db = {}
            # loadup the config.yaml which contains supported groups
            config = YAML::load_file(location + '/config.yaml')
            config.keys.each do |groupname|
                self[groupname] = load_group(groupname,location + '/' + groupname, config[groupname])
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
                grp = self[gname]
                raise 'No such news group' unless grp
                grp << [article, str]
            end
        end
    end
end


