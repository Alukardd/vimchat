" VImChat Plugin for vim
" This plugin allows you to connect to a jabber server and chat with
" multiple people.
"
" It does not currently support other IM networks or group chat, but these are
" on the list to be added.
"
" It currently only supports one jabber account at a time
" 

"Vim Commands/Functions
"{{{ Vim Commands/Functions
com! VimChatSignOff py vimChatSignOff()
com! VimChatSignOn py vimChatSignOn()
com! VimChatShowBuddyList :call VimChatShowBuddyList()

"Show the buddy list
map <Leader>vcb :call VimChatShowBuddyList()<CR>
"Connect to jabber
map <Leader>vcc :silent py vimChatSignOn()<CR>
"Disconnect from jabber
map <Leader>vcd :silent py vimChatSignOff()<CR>

set switchbuf=usetab
let g:rosterFile = '/tmp/vimChatRoster'

"Vim Functions
"{{{ VimChatShowBuddyList
function! VimChatShowBuddyList()
    try
        exe "silent vertical sview " . g:rosterFile
        exe "silent wincmd H"
    catch
        exe "tabe " . g:rosterFile
    endtry

    set nowrap

    nnoremap <buffer> <silent> <Return> :py vimChatBeginChat()<CR>
endfunction
"}}}

"}}}

""""""""""Python Stuff""""""""""""""
python <<EOF

#Imports/Global Vars
#{{{ imports/global vars
import vim
import vim,xmpp,select,threading
from datetime import time
from time import strftime

#Global Variables
chats = {}
chatServer = ""
chatMatches = {}
#}}}

#Classes
#{{{ class VimChat
class VimChat(threading.Thread):
    #Vim Executable to use
    _vim = 'vim'
    _rosterFile = '/tmp/vimChatRoster'
    _roster = {}

    #{{{ __init__
    def __init__(self, jid, password, callbacks):
        self._jid = jid
        self._password = password
        self._recievedMessage = callbacks
        threading.Thread.__init__ ( self )
    #}}}
    #{{{ run
    def run(self):
        jid=xmpp.protocol.JID(self._jid)
        self.jabber =xmpp.Client(jid.getDomain(),debug=[])

        con=self.jabber.connect()
        if not con:
            sys.stderr.write('could not connect!\n')
            sys.exit(1)

        auth=self.jabber.auth(
            jid.getNode(),
            self._password,
            resource=jid.getResource())

        if not auth:
            sys.stderr.write('could not authenticate!\n')
            sys.exit(1)

        self.jabber.RegisterHandler('message',self.jabberMessageReceive)
        self.jabber.RegisterHandler('presence',self.jabberPresenceReceive)
        self.jabber.sendInitPresence(requestRoster=1)

        #Socket stuff
        RECV_BUF = 4096
        self.xmppS = self.jabber.Connection._sock
        socketlist = [self.xmppS]
        online = 1

        print "Connected with VimChat (jid = " + self._jid + ")"

        while online:
            (i , o, e) = select.select(socketlist,[],[],1)
            for each in i:
                if each == self.xmppS:
                    self.jabber.Process(1)
                else:
                    pass
    #}}}

    #Roster Stuff
    #{{{ _writeRoster
    def _writeRoster(self):
        #write roster to file
        rF = open(self._rosterFile,'w')
        for item in self._roster.keys():
            name = str(item)
            priority = self._roster[item]['priority']
            show = self._roster[item]['show']
            if name and priority and show:
                try:
                    #TODO: figure out unicode stuff here
                    rF.write(name + "\n")
                except:
                    rF.write(name + "\n")

            else:
                rF.write(name + "\n")
                #rF.write("{{{ " + item + "\n" + item + "\n}}}\n")

        rF.close()
    #}}}
    #{{{ _clearRoster
    def _clearRoster(self,string):
        #write roster to file
        rF = open(self._rosterFile,'w')
        rF.write(string)
        rF.close()
    #}}}

    #From Jabber Functions
    #{{{ jabberMessageReceive
    def jabberMessageReceive(self, conn, msg):
        if msg.getBody():
            fromJid = str(msg.getFrom())
            body = str(msg.getBody())

            self._recievedMessage(fromJid, body)
    #}}}
    #{{{ jabberPresenceReceive
    def jabberPresenceReceive(self, conn, msg):
        jid = str(msg.getFrom())
        try:
            jid, resource = jid.split('/')
        except:
            resource = ""

        newPriority = msg.getPriority()

        self._roster[jid] = {
            'priority': msg.getPriority,
            'show':msg.getShow(),
            'status':msg.getStatus
        }

        #self._writeRoster()
    #}}}

    #To Jabber Functions
    #{{{ jabberSendMessage
    def jabberSendMessage(self, tojid, msg):
        msg = msg.strip()
        m = xmpp.protocol.Message(to=tojid,body=msg,typ='chat')
        #print 'Message: ' + msg
        self.jabber.send(m)
    #}}}
    #{{{ jabberPresenceUpdate
    def jabberPresenceUpdate(self, show, status):
        m = xmpp.protocol.Presence(
            self._jid,
            show=show,
            status=status)
        self.jabber.send(m)
    #}}}
    #{{{ disconnect
    def disconnect(self):
        try:
            self.jabber.disconnect()
        except:
            pass
    #}}}

    #{{{ getRoster
    def getRoster():
        return self._roster
    #}}}
#}}}

#General Functions
#{{{ getTimestamp
def getTimestamp():
    return strftime("[%H:%M]")
#}}}
#{{{ getBufByName
def getBufByName(name):
    for buf in vim.buffers:
        if buf.name == name:
            return buf
    return None
#}}}

#{{{ addBufMatch
def addBufMatch(buf, matchId):
    matchKeys = chatMatches.keys() 
    if buf in matchKeys:
        chatMatches[buf].append(matchId)
    else:
        chatMatches[buf] = []
        chatMatches[buf].append(matchId)
        
#}}}
#{{{ vimChatDeleteBufferMatches
def vimChatDeleteBufferMatches(buf):
    if buf in chatMatches.keys():
        for match in chatMatches[buf]:
            vim.command('call matchdelete(' + match + ')')

        chatMatches[buf] = []
#}}}

#{{{ vimChatBeginChat
def vimChatBeginChat():

    toJid = vim.current.line
    toJid = toJid.strip()


    user, domain = toJid.split('@')

    jid = toJid
    resource = ''
    if jid.find('/') >= 0:
        jid, resource = jid.split('/')

    chatKeys = chats.keys()
    chatFile = ''
    if toJid in chatKeys:
        chatFile = chats[toJid]
    else:
        chatFile = jid
        chats[toJid] = chatFile

    vim.command("q!")
    vim.command("split " + chatFile)

    vim.command("let b:buddyId = '" + toJid + "'")

    vimChatSetupChatBuffer();

#}}}
#{{{ vimChatSetupChatBuffer
def vimChatSetupChatBuffer():
    commands = """\
    setlocal noswapfile
    setlocal buftype=nowrite
    setlocal noai
    setlocal nocin
    setlocal nosi
    setlocal syntax=dcl
    setlocal wrap
    nnoremap <buffer> i :py vimChatSendBufferShow()<CR>
    nnoremap <buffer> o :py vimChatSendBufferShow()<CR>
    """
    vim.command(commands)

    vim.command('let b:id = ""')
    # This command has to be sent by itself.
    vim.command('au CursorMoved <buffer> py vimChatDeleteBufferMatches("' + \
        vim.current.buffer.name + '")')
#}}}
#{{{ vimChatSendBufferShow
def vimChatSendBufferShow():
    toJid = vim.eval('b:buddyId')

    origBuf = vim.current.buffer.name
    chats[toJid]= origBuf


    #Create sending buffer
    sendBuffer = "sendTo:" + toJid
    vim.command("silent bo new " + sendBuffer)

    vim.command("silent let b:buddyId = '" + toJid +  "'")

    commands = """\
        resize 4
        setlocal noswapfile
        setlocal nocin
        setlocal noai
        setlocal nosi
        setlocal buftype=nowrite
        setlocal wrap
        nnoremap <buffer> <CR> :py vimChatSendMessage()<CR>
        vnoremap <buffer> <CR> :py vimChatSendMessage()<CR>
    """
    vim.command(commands)
    vim.command('normal o')
    vim.command('normal zt')
    vim.command('star')

#}}}

#OUTGOING
#{{{ vimChatSendMessage
def vimChatSendMessage():
    try:
        toJid = vim.eval('b:buddyId')
    except:
        print "No valid chat found!"
        return 0


    r = vim.current.range
    body = ""
    for line in r:
        line = line.rstrip('\n')
        body = body + line + '\n'

    if body:
        global chatServer
        chatServer.jabberSendMessage(toJid, body)
    else:
        print "Nothing to send!"

    tstamp = getTimestamp()
    chatBuf = getBufByName(chats[toJid])
    if chatBuf:
        chatBuf.append(tstamp + " Me: " + body)
    else:
        print "Could not find where to append your message!"

    vim.command('hide')

    vim.command('sbuffer ' + str(chatBuf.number))
    vim.command('normal G')
#}}}

#INCOMING
#{{{ vimChatMessageReceived
def vimChatMessageReceived(fromJid, message):
    origBufNum = vim.current.buffer.number

    #get timestamp
    tstamp = getTimestamp()

    user, domain = fromJid.split('@')
    jid = fromJid
    resource = ''
    try:
        jid, resource = jid.split('/')
    except:
        resource = ""

    chatKeys = chats.keys()
    chatFile = ''
    if jid in chatKeys:
        chatFile = chats[jid]
    else:
        chatFile = jid
        chats[jid] = chatFile

    vim.command("bad " + chatFile)
    try:
        vim.command("sbuffer " + chatFile)
    except:
        vim.command("new " + chatFile)

    vim.command("let b:buddyId = '" + fromJid + "'")

    vimChatSetupChatBuffer();

    messageLines = message.split("\n")
    toAppend = tstamp + " " + user + '/' + resource + ": " + messageLines[0]
    messageLines.pop(0)
    vim.current.buffer.append(toAppend)

    for line in messageLines:
        line = tstamp + '\t' + line
        vim.current.buffer.append(line)

    vim.command("let b:lastMatchId =  matchadd('Error', '\%' . line('$') . 'l')")
    lastMatchId = vim.eval('b:lastMatchId')
    addBufMatch(chatFile,lastMatchId)
    vim.command("echo 'Message Received from: " + jid + "'")
    vim.command("sbuffer " + str(origBufNum))
#}}}
#{{{ vimChatSignOn
def vimChatSignOn():
    global chatServer

    if chatServer:
        print "Already connected to VimChat!"
        return 0
    else:
        print "Connecting..."

    jid = vim.eval('g:vimchat_jid')
    password = vim.eval('g:vimchat_password')

    chatServer = VimChat(jid, password,vimChatMessageReceived)
    chatServer.start()
    
#}}}
#{{{ vimChatSignOff
def vimChatSignOff():
    global chatServer
    if chatServer:
        try:
            chatServer.disconnect()
            print "Signed Off VimChat!"
        except Exception, e:
            print "Error signing off VimChat!"
            print e
    else:
        print "Not Connected!"
#}}}

EOF
" vim:et:fdm=marker:sts=4:sw=4:ts=4
