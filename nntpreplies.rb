module NNTPReplies
RPL_PWELCOME		= 200 #server ready - posting allowed
RPL_WELCOME         = 201 #server ready - no posting allowed
#   202 slave status noted
RPL_QUIT            = 205 #closing connection - goodbye!
RPL_GSELECT         = 211 #n f l s group selected
RPL_GLIST           = 215 #list of newsgroups follows
RPL_ARTICLE         = 220 #n <a> article retrieved - head and body follow 221 n <a> article
#   retrieved - head follows
#   222 n <a> article retrieved - body follows
#   223 n <a> article retrieved - request text separately 230 list of new
#   articles by message-id follows
RPL_ALIST           = 224 #XOVER
RPL_NEWGROUPS       = 231 #list of new newsgroups follows
#   235 article transferred ok
RPL_POSTOK          = 240 #article posted ok
#
#   335 send article to be transferred.  End with <CR-LF>.<CR-LF>
RPL_SENDPOST        = 340 #send article to be posted. End with <CR-LF>.<CR-LF>
#
#   400 service discontinued
ERR_NOSUCHGROUP     = 411 #no such news group
#   412 no newsgroup has been selected
#   420 no current article has been selected
#   421 no next article in this group
#   422 no previous article in this group
ERR_NOSUCHARTICLE  = 423 #no such article number in this group
#   430 no such article found
#   435 article not wanted - do not send it
#   436 transfer failed - try again later
#   437 article rejected - do not try again.
#   440 posting not allowed
#   441 posting failed
#
ERR_UNKNOWNCOMMAND  = 500 #command not recognized
ERR_CMDSYNTAX       = 501 #command syntax error
#   502 access restriction or permission denied
#   503 program fault - command not performed
end
