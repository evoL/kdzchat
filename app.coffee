http = require 'http'
url = require 'url'
fs = require 'fs'
socketio = require 'socket.io'

DEBUG = false

############### file handling functions

publicFile = (name) -> [__dirname, 'public', name].join('/')

mimeType = (name) ->
    return 'text/html' if name.match(/.html$/)
    return 'text/javascript' if name.match(/\.js$/)
    return 'text/css' if name.match(/.css$/)

    'text/plain'

readFile = (name, res) ->
    return false unless fs.existsSync(name)

    fs.readFile name, (err, data) ->
        if err
            console.log("[500] file #{name}") if DEBUG
            res.writeHead(500)
            return res.end("Could not load file #{name}")

        console.log("[200] file #{name}") if DEBUG
        res.writeHead(200, {'Content-Type': mimeType(name)})
        res.end(data)

    return true

############### handlers

serveStaticFiles = (path, res) ->
    filename = [__dirname, 'public'].join('/') + path

    readFile filename, res

router = (path, res) ->
    switch path
        when '/' then readFile publicFile('index.html'), res
        else return false

############### server

server = http.createServer (request, response) ->
    parsed_url = url.parse(request.url)

    console.log("[...] #{parsed_url.pathname}") if DEBUG

    handlers = [router, serveStaticFiles]

    unless handlers.some((h) -> h(parsed_url.pathname, response))
        console.log("[404] #{parsed_url.pathname}") if DEBUG
        response.writeHead(404)
        response.end("Path #{parsed_url.pathname} not found")

############### socket.io

io = socketio.listen(server)
users = {}
counter = 0

io.sockets.on 'connection', (socket) ->
    socket.on 'add user', (data, ack) ->
        data.id = 'user-' + counter++
        socket.user = data
        users[data.id] = data
        ack(data, users)

        socket.broadcast.emit('user connected', data)

    socket.on 'change nick', (data) ->
        data.oldNick = socket.user.nick

        socket.user.nick = data.nick
        users[data.id].nick = data.nick

        socket.broadcast.emit('nick changed', data)

    socket.on 'disconnect', ->
        delete users[socket.user.id]
        io.sockets.emit('user disconnected', socket.user)
        socket.user = null

    socket.on 'chat', (data) ->
        socket.broadcast.emit 'chat', 
            authorId: socket.user.id
            content: data.content

################ proxy

server.listen(8999)