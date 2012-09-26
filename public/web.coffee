# socket = io.connect('http://localhost:8888')

# socket.on 'news', (data) ->
#     console.log data
#     socket.emit('some event', {data: 'data'})

class @User extends Spine.Model
    @configure 'User', 'id', 'nick', 'current'

    validate: ->
        unless @nick.match(/^[\w\-]+$/)
            "The nick should only contain alphanumeric characters, hyphens and underscores"

        if User.findByAttribute('nick', @nick)
            'This user already exists'

class @Message extends Spine.Model
    @configure 'Message', 'authorId', 'content'

    validate: ->
        unless User.exists(@authorId)
            "The user doesn't exist"

# class SocketTransport
#     constructor: ->


# class SocketHandler
#     constructor: ->
#         @socket = io.connect(location.origin)
#         @socket.on 'server', @process

#     onDisconnect: (fn) ->
#         @socket.on('disconnect', fn)

#     send: (packet) ->
#         @socket.emit 'client', packet

#     process: (data) =>
#         console.log data

#         throw "No model specified" unless data.model?

#         switch data.model
#             when 'User'
#                 switch data.event
#                     when 'create'
#                         data.record.current = false
#                         User.create data.record unless User.exists(data.record.id)
#                     when 'update'
#                         data.record.current = false
#                         User.update data.id, data.record
#                     when 'destroy'
#                         User.destroy data.id
#                     else
#                         throw 'Unknown event for User: ' + data.event
#             when 'Message'
#                 Message.create data.record unless Message.exists(data.record.id)
#             else
#                 throw 'Unknown model specified: ' + data.model

###################

class Messages extends Spine.Controller
    constructor: ->
        super
        @el.addClass 'post'

    data: ->
        author: User.find(@message.authorId).nick
        content: @processMessage(@message.content)

    processMessage: (text) ->
        rx = /((?:http|https):&#x2F;&#x2F;)?([a-z0-9-]+\.)?[a-z0-9-]+(\.[a-z]{2,6}){1,3}(&#x2F;(?:[a-z0-9.,_~#&=;%+?-]|&#x2F;)*)?/ig
        Mustache.escape(text).replace rx, (match, protocol) ->
            url = if protocol? then match else "//#{match}"
            "<a href=\"#{url}\" target=\"_blank\">#{match}</a>"

    render: =>
        @html Mustache.render($('#MessageTemplate').text(), @data())
        @

class UserList extends Spine.Controller
    constructor: ->
        super
        User.bind('refresh change', @render)

    data: ->
        count: User.count()
        users: User.all().map (user) =>
            current: user.current
            name: user.nick

    render: =>
        @html Mustache.render($('#UserListTemplate').text(), @data())
        @

class ChatApp extends Spine.Controller
    elements:
        '#ChatInput': 'input'
        '#ChatArea': 'posts'
        '.chatarea-wrapper': 'scrollArea'
        '#UserList': 'userlist'

    events:
        'submit #InputForm': 'submit'

    constructor: ->
        super
        Message.bind('create', @addMessage)

        @users = new UserList(el: @userlist)

        @socket = io.connect()
        @socket.on 'connect', =>
            @socket.emit 'add user', {nick: @randomizeNick()}, (data, users) =>
                @user = User.create(id: data.id, nick: data.nick, current: true)

                for uid, userdata of users
                    if uid != data.id
                        User.create(id: userdata.id, nick: userdata.nick, current: false)

        @socket.on 'user connected', (data) ->
            data.current = false
            User.create data unless User.exists(data.id)
        @socket.on 'user disconnected', (uid) ->
            User.destroy uid

        @socket.on 'chat', (msg) ->
            Message.create msg

    submit: (e) ->
        e.preventDefault()
        Message.create(authorId: @user.id, content: @input.val())
        @socket.emit 'chat', {content: @input.val()}

        @input.val('')

    addMessage: (msg) =>
        view = new Messages(message: msg)
        @posts.append(view.render().el)
        @scrollArea.scrollTop(@scrollArea.height())

    randomizeNick: ->
        index = Math.floor(Math.random() * 100000);
        "guest#{index}"

$ -> new ChatApp(el: $('#Viewport'))