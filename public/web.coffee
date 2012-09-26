class User extends Spine.Model
    @configure 'User', 'id', 'nick', 'current'

    validate: ->
        unless /^[\w\-]+$/.test(@nick)
            return "The nick should only contain alphanumeric characters, hyphens and underscores."

        if User.findByAttribute('nick', @nick)
            return 'This user already exists.'

class Message extends Spine.Model
    @configure 'Message', 'authorId', 'content'

    constructor: ->
        super

        match = @content.match(/^\/(\w+)\s+(.+)$/)
        if match
            @metadata = {command: match[1], argument: match[2]}        

    isSystemMessage: -> @metadata?

    validate: ->
        unless User.exists(@authorId)
            "The user doesn't exist."

class SystemMessage extends Spine.Model
    @configure 'SystemMessage', 'authorId', 'content'    

    isSystemMessage: -> true

    validate: ->
        unless User.exists(@authorId)
            "The user doesn't exist."

##################################

socket = io.connect("#{location.protocol}//#{location.hostname}:8999")

class Messages extends Spine.Controller
    constructor: ->
        super
        @el.addClass 'post'
        @el.addClass 'system' if @message.isSystemMessage()

    messageContent: ->
        return @processMessage(@message.content) unless @message.isSystemMessage()

        metadata = @message.metadata

        return @processMessage(@message.content) unless metadata

        switch metadata.command
            when 'nick'
                user = User.find(@message.authorId)
                user.nick = metadata.argument.replace(/\s+$/, '')

                if user.save()
                    socket.emit 'change nick', {id: @message.authorId, nick: user.nick}
                    "is now called " + Mustache.escape(user.nick)
                else
                    msg = user.validate()
                    "could not change his nick. " + msg
            else
                "tried to use an unknown command"

    data: ->
        author: User.find(@message.authorId).nick
        content: @messageContent()

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
        @input.focus()

        Message.bind('create', @addMessage)
        SystemMessage.bind('create', @addMessage)

        @users = new UserList(el: @userlist)

        socket.on 'connect', =>
            socket.emit 'add user', {nick: @randomizeNick()}, (data, users) =>
                @user = User.create(id: data.id, nick: data.nick, current: true)

                for uid, userdata of users
                    if uid != data.id
                        User.create(id: userdata.id, nick: userdata.nick, current: false)

        socket.on 'user connected', (data) =>
            data.current = false
            User.create data unless User.exists(data.id)

            SystemMessage.create(authorId: data.id, content: 'has just connected')
        socket.on 'user disconnected', (uid) ->
            User.destroy uid

            # SystemMessage.create(authorId: data.id, content: 'has disconnected')
        socket.on 'nick changed', (data) ->
            User.update data.id, nick: data.nick

            SystemMessage.create(authorId: data.id, content: 'has changed his nick from ' + data.oldNick)

        socket.on 'chat', (msg) ->
            Message.create msg

    submit: (e) ->
        e.preventDefault()
        msg = Message.create(authorId: @user.id, content: @input.val())
        unless msg.isSystemMessage()
            socket.emit 'chat', {content: @input.val()}

        @input.val('')

    addMessage: (msg) =>
        view = new Messages(message: msg)
        @posts.append(view.render().el)
        @scrollArea.scrollTop(@scrollArea.height())

    randomizeNick: ->
        index = Math.floor(Math.random() * 100000);
        "guest#{index}"

$ -> new ChatApp(el: $('#Viewport'))