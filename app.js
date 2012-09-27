// Generated by CoffeeScript 1.3.3
(function() {
  var DEBUG, counter, fs, http, io, mimeType, publicFile, readFile, router, serveStaticFiles, server, socketio, url, users;

  http = require('http');

  url = require('url');

  fs = require('fs');

  socketio = require('socket.io');

  DEBUG = false;

  publicFile = function(name) {
    return [__dirname, 'public', name].join('/');
  };

  mimeType = function(name) {
    if (name.match(/.html$/)) {
      return 'text/html';
    }
    if (name.match(/\.js$/)) {
      return 'text/javascript';
    }
    if (name.match(/.css$/)) {
      return 'text/css';
    }
    return 'text/plain';
  };

  readFile = function(name, res) {
    if (!fs.existsSync(name)) {
      return false;
    }
    fs.readFile(name, function(err, data) {
      if (err) {
        if (DEBUG) {
          console.log("[500] file " + name);
        }
        res.writeHead(500);
        return res.end("Could not load file " + name);
      }
      if (DEBUG) {
        console.log("[200] file " + name);
      }
      res.writeHead(200, {
        'Content-Type': mimeType(name)
      });
      return res.end(data);
    });
    return true;
  };

  serveStaticFiles = function(path, res) {
    var filename;
    filename = [__dirname, 'public'].join('/') + path;
    return readFile(filename, res);
  };

  router = function(path, res) {
    switch (path) {
      case '/':
        return readFile(publicFile('index.html'), res);
      default:
        return false;
    }
  };

  server = http.createServer(function(request, response) {
    var handlers, parsed_url;
    parsed_url = url.parse(request.url);
    if (DEBUG) {
      console.log("[...] " + parsed_url.pathname);
    }
    handlers = [router, serveStaticFiles];
    if (!handlers.some(function(h) {
      return h(parsed_url.pathname, response);
    })) {
      if (DEBUG) {
        console.log("[404] " + parsed_url.pathname);
      }
      response.writeHead(404);
      return response.end("Path " + parsed_url.pathname + " not found");
    }
  });

  io = socketio.listen(server);

  users = {};

  counter = 0;

  io.sockets.on('connection', function(socket) {
    socket.on('add user', function(data, ack) {
      data.id = 'user-' + counter++;
      socket.user = data;
      users[data.id] = data;
      ack(data, users);
      return socket.broadcast.emit('user connected', data);
    });
    socket.on('change nick', function(data) {
      data.oldNick = socket.user.nick;
      socket.user.nick = data.nick;
      users[data.id].nick = data.nick;
      return socket.broadcast.emit('nick changed', data);
    });
    socket.on('disconnect', function() {
      delete users[socket.user.id];
      io.sockets.emit('user disconnected', socket.user);
      return socket.user = null;
    });
    return socket.on('chat', function(data) {
      if (data.content === '') {
        return;
      }
      return socket.broadcast.emit('chat', {
        authorId: socket.user.id,
        content: data.content
      });
    });
  });

  server.listen(8999);

}).call(this);
