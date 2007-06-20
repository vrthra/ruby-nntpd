require 'utils'
module NNTPD
    class CatLog
        def parse(lines)
            tcases = []
            elem = nil
            summary = Elem.new
            fails = 0
            lines.each do |s|
                case s 
                when /^\>(.*)$/
                    elem = Elem.new
                    elem.subject = $1.strip
                    elem << s
                    tcases << elem
                when /^CTE /
                    summary << s
                    tcases << elem if elem
                    elem = nil
                when /^stat : \(([0-9]+)\/[0-9]+\)/
                    elem.subject = elem.subject + (fails == $1.strip.to_i ? ' passed':' failed')
                    fails = $1.strip.to_i
                    elem << s
                else
                    elem << s if elem
                end
            end
            summary.subject = "cat summary #{fails} failed"
            return tcases,summary
        end
    end

    class ParseCat < BaseGroup
        def initialize(name,path,config)
            super(name,path,config)
            @last = 0
            # iterate throu path, registering each article we find
            print "Loading cat #{@name} #{path}"
            Dir.mkdir path rescue puts "+"
            Dir[path + '/*'].sort{|a,b|File.basename(a).to_i <=>File.basename(b).to_i}.each do |afile|
                puts "\tarticle #{afile}"
                localstart = @last + 1
                begin
                    articles = LogArticle.parse(File.open(afile).readlines, CatLog.new)
                    print "."

                    # for each articles.
                    articles.each do |article|
                        @last += 1
                        self[@last]= article # keeps only the overview information
                    end

                    # for the particular file in the range
                    LogCache.register((localstart .. @last), afile)
                rescue Exception => e
                    puts "Invalid article #{afile}"
                    puts e.message
                    puts e.backtrace
                end
            end
            puts ""
        end

        def <<(arr)
            article = arr[0]
            buf = arr[1]

            path = @path + '/' + (@last + 1).to_s
            startid = @last + 1

            File.open(path,'w+') {|fd| fd.print buf}

            articles = LogArticle.parse(buf.split("\n"), CatLog.new)
            articles.each do |a|
                @last += 1
                self[@last.to_s] = a # keeps only the overview information
            end
            # we need to putin ourselves too.
            LogCache.register(startid .. @last, path)
        end
    end
end

