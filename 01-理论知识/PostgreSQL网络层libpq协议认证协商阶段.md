当加密协商阶段完成或跳过，PostgreSQL协议将开始进行认证阶段。认证阶段由Startup message消息开始，其消息格式为：
![Image text](./_media/2971f03ca7e24e99a1faf3be6b0eaa42.png)

其中特殊值TAG为一个4字节的网络字节序的int值，为196608(0x30000)，并且这个TAG值也描述了PostgreSQL协议的版本号，其major version为3，minor version为0.其中内容为一系列的key-value对，描述了前端的一些配置参数。

```
	case CONNECTION_MADE: {
            ...
        		/* Build the startup packet. 构建启动包 */
				if (PG_PROTOCOL_MAJOR(conn->pversion) >= 3) startpacket = pqBuildStartupPacket3(conn, &packetlen, EnvironmentOptions);
				else startpacket = pqBuildStartupPacket2(conn, &packetlen, EnvironmentOptions);
				if (!startpacket) {
					/* will not appendbuffer here, since it's likely to also run out of memory 不会在这里追加缓冲区，因为它也可能会耗尽内存 */
					printfPQExpBuffer(&conn->errorMessage, libpq_gettext("out of memory\n"));
					goto error_return;
				}
				/* Send the startup packet. Theoretically, this could block, but it really shouldn't since we only got here if the socket is write-ready. 发送启动包。 理论上，这可能会阻塞，但它真的不应该，因为我们只有在套接字准备好写入时才到达这里 */
				if (pqPacketSend(conn, 0, startpacket, packetlen) != STATUS_OK) {
					appendPQExpBuffer(&conn->errorMessage, libpq_gettext("could not send startup packet: %s\n"), SOCK_STRERROR(SOCK_ERRNO, sebuf, sizeof(sebuf)));
					free(startpacket);
					goto error_return;
				}
				free(startpacket);
				conn->status = CONNECTION_AWAITING_RESPONSE;
				return PGRES_POLLING_READING;
			}		
```

当前端发出Startup message消息后，后端会进行认证应答，认证应答信息的类型为’R’，其内容大致分为3种情况：完成认证（相当于不需要认证）、提供认证方式与所需的参数、认证错误。
![Image text](./_media/a52b9825113648a8a4c1bea6d1bb0bec.png)

当后端通过Startup message消息中的内容就可以获取一些前端的会话信息，例如用户名。数据库名，工具名等，那么后端就会根据配置去匹配某些认证规则，并根据规则所要求的认证方式进行认证协商。认证错误消息ErrorResponse会导致后端直接关闭连接，停止认证协商。
![Image text](./_media/1290484cc84e4953b11657868236b08a.png)

常用的认证方式大概有以下几种：无认证（或认证完成）、CleartextPassword明文密码、MD5Password密码的MD5（其中内容中有4字节的salt值）
还用一些不常用的认证方式：KerberosV5、SCMCredential、GSSAPI、SASL。其中当后端认为Startup message中的协议版本号不在后端的支持范围内的时候，后端可能会断开连接，或通过NegotiateProtocilVersion认证方式提供后端所支持的版本号。

```
 // 服务端ProcessStartupPacket函数部分代码
	if (PG_PROTOCOL_MAJOR(proto) >= 3) {
		int32		offset = sizeof(ProtocolVersion);
		List	   *unrecognized_protocol_options = NIL;
		/* Scan packet body for name/option pairs.  We can assume any string
		 * beginning within the packet body is null-terminated, thanks to
		 * zeroing extra byte above. */
		port->guc_options = NIL;
		while (offset < len){
			char	   *nameptr = ((char *) buf) + offset; int32		valoffset; char	   *valptr;
			if (*nameptr == '\0')break;			/* found packet terminator */
			valoffset = offset + strlen(nameptr) + 1;
			if (valoffset >= len) break;			/* missing value, will complain below */
			valptr = ((char *) buf) + valoffset;
			if (strcmp(nameptr, "database") == 0) port->database_name = pstrdup(valptr);
			else if (strcmp(nameptr, "user") == 0) port->user_name = pstrdup(valptr);
			else if (strcmp(nameptr, "options") == 0) port->cmdline_options = pstrdup(valptr);
			else if (strcmp(nameptr, "replication") == 0){
				if (strcmp(valptr, "database") == 0) {
					am_walsender = true;
					am_db_walsender = true;
				}else if (!parse_bool(valptr, &am_walsender))
					ereport(FATAL,(errcode(ERRCODE_INVALID_PARAMETER_VALUE),errmsg("invalid value for parameter \"%s\": \"%s\"","replication",valptr),errhint("Valid values are: \"false\", 0, \"true\", 1, \"database\".")));
			}else if (strncmp(nameptr, "_pq_.", 5) == 0){  // 协议级别选项
				/* Any option beginning with _pq_. is reserved for use as a protocol-level option, but at present no such options are defined. */
				unrecognized_protocol_options = lappend(unrecognized_protocol_options, pstrdup(nameptr));
			}else{
				/* Assume it's a generic GUC option */
				port->guc_options = lappend(port->guc_options,pstrdup(nameptr));
				port->guc_options = lappend(port->guc_options,pstrdup(valptr));
				if (strcmp(nameptr, "application_name") == 0){
					char	   *tmp_app_name = pstrdup(valptr);
					pg_clean_ascii(tmp_app_name);
					port->application_name = tmp_app_name;
				}
			}
			offset = valoffset + strlen(valptr) + 1;
		}

		/* If we didn't find a packet terminator exactly at the end of the given packet length, complain. */
		if (offset != len - 1) ereport(FATAL,(errcode(ERRCODE_PROTOCOL_VIOLATION),errmsg("invalid startup packet layout: expected terminator as last byte")));

		/* If the client requested a newer protocol version or if the client
		 * requested any protocol options we didn't recognize, let them know
		 * the newest minor protocol version we do support and the names of
		 * any unrecognized options. 如果客户端请求更新的协议版本，或者如果客户端请求任何我们无法识别的协议选项，请让他们知道我们支持的最新次要协议版本以及任何无法识别的选项的名称。 */
		if (PG_PROTOCOL_MINOR(proto) > PG_PROTOCOL_MINOR(PG_PROTOCOL_LATEST) || unrecognized_protocol_options != NIL)
			SendNegotiateProtocolVersion(unrecognized_protocol_options);
	}
```


PostgreSQL数据库安全——用户标识和认证中描述了调用PerformAuthentication函数认证远程客户端。
```
/* PerformAuthentication -- authenticate a remote client
 * returns: nothing.  Will not return at all if there's any failure. */
static void PerformAuthentication(Port *port) {
	/* This should be set already, but let's make sure */
	ClientAuthInProgress = true;	/* limit visibility of log messages */
	/* In EXEC_BACKEND case, we didn't inherit the contents of pg_hba.conf etcetera from the postmaster, and have to load them ourselves. FIXME: [fork/exec] Ugh.  Is there a way around this overhead? 在 EXEC_BACKEND 的情况下，我们没有从 postmaster 继承 pg_hba.conf 等的内容，并且必须自己加载它们。*/
#ifdef EXEC_BACKEND
	/* load_hba() and load_ident() want to work within the PostmasterContext, so create that if it doesn't exist (which it won't).  We'll delete it again later, in PostgresMain. */
	if (PostmasterContext == NULL) PostmasterContext = AllocSetContextCreate(TopMemoryContext, "Postmaster", ALLOCSET_DEFAULT_SIZES);
	if (!load_hba()) {
		/* It makes no sense to continue if we fail to load the HBA file, since there is no way to connect to the database in this case. 如果我们无法加载 HBA 文件，则继续没有意义，因为在这种情况下无法连接到数据库 */
		ereport(FATAL, (errmsg("could not load pg_hba.conf")));
	}
	if (!load_ident()) {
		/* It is ok to continue if we fail to load the IDENT file, although it means that you cannot log in using any of the authentication methods that need a user name mapping. load_ident() already logged the details of error to the log. 如果我们无法加载 IDENT 文件，可以继续，尽管这意味着您无法使用任何需要用户名映射的身份验证方法登录。 load_ident() 已经在日志中记录了错误的详细信息 */
	}
#endif

	/* Set up a timeout in case a buggy or malicious client fails to respond during authentication.  Since we're inside a transaction and might do database access, we have to use the statement_timeout infrastructure. 设置超时以防错误或恶意客户端在身份验证期间无法响应。 由于我们在事务中并且可能进行数据库访问，我们必须使用 statement_timeout 基础设施 */
	enable_timeout_after(STATEMENT_TIMEOUT, AuthenticationTimeout * 1000);
	/* Now perform authentication exchange. */
	ClientAuthentication(port); /* might not return, if failure */	
	disable_timeout(STATEMENT_TIMEOUT, false); /* Done with authentication.  Disable the timeout, and log if needed. */
	if (Log_connections){
		StringInfoData logmsg;
		initStringInfo(&logmsg);
		if (am_walsender) appendStringInfo(&logmsg, _("replication connection authorized: user=%s"), port->user_name);
		else appendStringInfo(&logmsg, _("connection authorized: user=%s"), port->user_name);
		if (!am_walsender) appendStringInfo(&logmsg, _(" database=%s"), port->database_name);
		if (port->application_name != NULL) appendStringInfo(&logmsg, _(" application_name=%s"), port->application_name);
#ifdef USE_SSL
		if (port->ssl_in_use) appendStringInfo(&logmsg, _(" SSL enabled (protocol=%s, cipher=%s, bits=%d, compression=%s)"), be_tls_get_version(port), be_tls_get_cipher(port), be_tls_get_cipher_bits(port), be_tls_get_compression(port) ? _("on") : _("off"));
#endif
#ifdef ENABLE_GSS
		if (port->gss) {
			const char *princ = be_gssapi_get_princ(port);
			if (princ) appendStringInfo(&logmsg, _(" GSS (authenticated=%s, encrypted=%s, principal=%s)"), be_gssapi_get_auth(port) ? _("yes") : _("no"), be_gssapi_get_enc(port) ? _("yes") : _("no"), princ);
			else appendStringInfo(&logmsg,_(" GSS (authenticated=%s, encrypted=%s)"), be_gssapi_get_auth(port) ? _("yes") : _("no"), be_gssapi_get_enc(port) ? _("yes") : _("no"));
		}
#endif
		ereport(LOG, errmsg_internal("%s", logmsg.data));
		pfree(logmsg.data);
	}
	set_ps_display("startup", false);
	ClientAuthInProgress = false;	/* client_min_messages is active now */
}
```

ClientAuthentication函数是PerformAuthentication函数中真正进行客户认证工作的函数。首先获取此前端/数据库组合的身份验证方法，将匹配的hba条目HbaLine赋值到port->hba中
```
void ClientAuthentication(Port *port) {
	int			status = STATUS_ERROR;
	char	   *logdetail = NULL;
	/* Get the authentication method to use for this frontend/database
	 * combination.  Note: we do not parse the file at this point; this has
	 * already been done elsewhere.  hba.c dropped an error message into the
	 * server logfile if parsing the hba config file failed. */
	hba_getauthmethod(port);

```
这是我们可以访问当前连接的 hba 记录的第一个点，因此基于 hba 选项字段执行任何验证，这些验证应该在此处完成身份验证之前做。

```
if (port->hba->clientcert != clientCertOff) {
		/* If we haven't loaded a root certificate store, fail */
		if (!secure_loaded_verify_locations())
			ereport(FATAL,(errcode(ERRCODE_CONFIG_FILE_ERROR),errmsg("client certificates can only be checked if a root certificate store is available")));
		/* If we loaded a root certificate store, and if a certificate is present on the client, then it has been verified against our root certificate store, and the connection would have been aborted already if it didn't verify ok. */
		if (!port->peer_cert_valid)
			ereport(FATAL,(errcode(ERRCODE_INVALID_AUTHORIZATION_SPECIFICATION), errmsg("connection requires a valid client certificate")));
	}
```
执行真正的认证工作，即针对不同的认证方式调用不同的方法。注意这里有一个ClientAuthentication_hook钩子，可以用来审计客户端登入认证的详细信息。
```
switch (port->hba->auth_method) {
		case uaReject: // pg_hba.conf 中的显式“拒绝”条目。 这份报告揭示了一个事实，即有一个明确的拒绝条目，从安全角度来看，这可能不是那么理想； 但是当真实情况与显式拒绝匹配时，隐式拒绝的消息可能会使 DBA 很困惑。 而且我们不想将消息更改为隐式拒绝。 如下所述，此处显示的附加信息不会向攻击者公开任何未知的信息。
        case uaImplicitReject: // 没有匹配的条目，所以告诉用户我们失败了。 注意：这里报告的额外信息不是安全漏洞，因为所有这些信息在前端都是已知的，并且必须假定坏人知道。 我们只是在帮助那些不太聪明的好人。
        case uaGSS:	
        case uaSSPI:
        case uaPeer:
        case uaIdent: status = ident_inet(port); break;
        case uaMD5:
        case uaSCRAM: status = CheckPWChallengeAuth(port, &logdetail); break;
        case uaPassword: status = CheckPasswordAuth(port, &logdetail); 	break;
 		case uaPAM: status = CheckPAMAuth(port, port->user_name, ""); break;
		case uaBSD: status = CheckBSDAuth(port, port->user_name); break;
		case uaLDAP: status = CheckLDAPAuth(port); break;
		case uaRADIUS: status = CheckRADIUSAuth(port); break;
		case uaCert: /* uaCert will be treated as if clientcert=verify-full (uaTrust) */
		case uaTrust: status = STATUS_OK; break;
	}   
	if ((status == STATUS_OK && port->hba->clientcert == clientCertFull) || port->hba->auth_method == uaCert) {
		/* Make sure we only check the certificate if we use the cert method or verify-full option. */
#ifdef USE_SSL
		status = CheckCertAuth(port);
#endif		
	}
	if (ClientAuthentication_hook) (*ClientAuthentication_hook) (port, status);
	if (status == STATUS_OK) sendAuthRequest(port, AUTH_REQ_OK, NULL, 0);
	else auth_failed(port, status, logdetail);	 
```

这里以MD5认证为例，从上面的代码可知MD5认证调用了CheckPWChallengeAuth(port, &logdetail)函数，在认证成功的情况下调用了sendAuthRequest(port, AUTH_REQ_OK, NULL, 0)函数。
前端通过认证应答信息提供的认证方式（如果有的话）向后端发送认证请求，认证请求消息中包含后端所需要的认证参数，例如密码或密码的MD5值等。认证请求的类型为’p’，其内容需要根据上下文进行推断，例如之前认证应答消息中的认证方式MD5，则认证请求消息中的内容就为密码的MD5值。
前端向后端发送认证请求后，后端会再次根据认证请求中的内容进行认证应答，直到认证完成或认证错误。所以认证阶段完成的标志为后端发送了内容为认证完成的认证应答消息或发送了ErrorResponse的认证错误消息。

![Image text](./_media/1b4487f7ac654bf1bb3be2b63110cfbf.png)

客户端尝试为此连接推进状态机，为CONNECTION_AWAITING_RESPONSE状态进行认证交互。

```
	/* Handle authentication exchange: wait for postmaster messages and respond as necessary. */
		case CONNECTION_AWAITING_RESPONSE: {
				char		beresp;
				int			msgLength; int			avail; int			res;		
				AuthRequest areq;				
				/* Scan the message from current point (note that if we find the message is incomplete, we will return without advancing inStart, and resume here next time). 从当前点扫描消息（注意，如果发现消息不完整，我们将不前进 inStart 就返回，下次在这里继续） */
				conn->inCursor = conn->inStart;				
				if (pqGetc(&beresp, conn)) { /* Read type byte */					
					return PGRES_POLLING_READING; /* We'll come back when there is more data */
				}
				/* Validate message type: we expect only an authentication request or an error here.  Anything else probably means it's not Postgres on the other end at all. 验证消息类型：我们希望这里只有一个身份验证请求或一个错误。 其他任何事情都可能意味着它根本不是另一端的 Postgres */
				if (!(beresp == 'R' || beresp == 'E')){
					appendPQExpBuffer(&conn->errorMessage,libpq_gettext("expected authentication request from server, but received %c\n"), beresp);
					goto error_return;
				}
				if (PG_PROTOCOL_MAJOR(conn->pversion) >= 3){					
					if (pqGetInt(&msgLength, 4, conn)){ /* Read message length word */											
						return PGRES_POLLING_READING; /* We'll come back when there is more data */
					}
				}else{					
					msgLength = 8; /* Set phony message length to disable checks below */
				}
				/* Try to validate message length before using it. Authentication requests can't be very large, although GSS auth requests may not be that small.  Errors can be a little larger, but not huge.  If we see a large apparent length in an error, it means we're really talking to a pre-3.0-protocol server; cope. */
				if (beresp == 'R' && (msgLength < 8 || msgLength > 2000)){
					appendPQExpBuffer(&conn->errorMessage, libpq_gettext("expected authentication request from server, but received %c\n"), beresp);
					goto error_return;
				}
				if (beresp == 'E' && (msgLength < 8 || msgLength > 30000)){
					/* Handle error from a pre-3.0 server */
					conn->inCursor = conn->inStart + 1; /* reread data */
					if (pqGets_append(&conn->errorMessage, conn)){
						/* We'll come back when there is more data */
						return PGRES_POLLING_READING;
					}
					/* OK, we read the message; mark data consumed */
					conn->inStart = conn->inCursor;

					/* The postmaster typically won't end its message with a newline, so add one to conform to libpq conventions. postmaster通常不会以换行符结束它的消息，所以添加一个以符合 libpq 约定 */
					appendPQExpBufferChar(&conn->errorMessage, '\n');
					/* If we tried to open the connection in 3.0 protocol, fall back to 2.0 protocol. 如果我们尝试在 3.0 协议中打开连接，请回退到 2.0 协议 */
					if (PG_PROTOCOL_MAJOR(conn->pversion) >= 3){
						conn->pversion = PG_PROTOCOL(2, 0);
						need_new_connection = true;
						goto keep_going;
					}
					goto error_return;
				}

				/* Can't process if message body isn't all here yet.
				 * (In protocol 2.0 case, we are assuming messages carry at least 4 bytes of data.) */
				msgLength -= 4;
				avail = conn->inEnd - conn->inCursor;
				if (avail < msgLength){
					/* Before returning, try to enlarge the input buffer if needed to hold the whole message; see notes in pqParseInput3. */
					if (pqCheckInBufferSpace(conn->inCursor + (size_t) msgLength, conn))
						goto error_return;					
					return PGRES_POLLING_READING; /* We'll come back when there is more data */
				}
			
				if (beresp == 'E') { /* Handle errors. */
					if (PG_PROTOCOL_MAJOR(conn->pversion) >= 3){
						if (pqGetErrorNotice3(conn, true)){						
							return PGRES_POLLING_READING; /* We'll come back when there is more data */
						}
					}else{
						if (pqGets_append(&conn->errorMessage, conn)){					
							return PGRES_POLLING_READING; /* We'll come back when there is more data */
						}
					}
					/* OK, we read the message; mark data consumed */
					conn->inStart = conn->inCursor;
					/* Check to see if we should mention pgpassfile */
					pgpassfileWarning(conn);
#ifdef ENABLE_GSS

					/* If gssencmode is "prefer" and we're using GSSAPI, retry without it. */
					if (conn->gssenc && conn->gssencmode[0] == 'p') {
						/* only retry once */
						conn->try_gss = false;
						need_new_connection = true;
						goto keep_going;
					}
#endif

#ifdef USE_SSL
					/* if sslmode is "allow" and we haven't tried an SSL connection already, then retry with an SSL connection */
					if (conn->sslmode[0] == 'a' /* "allow" */&& !conn->ssl_in_use&& conn->allow_ssl_try&& conn->wait_ssl_try){
						/* only retry once */
						conn->wait_ssl_try = false;
						need_new_connection = true;
						goto keep_going;
					}
					/* if sslmode is "prefer" and we're in an SSL connection, then do a non-SSL retry */
					if (conn->sslmode[0] == 'p' /* "prefer" */&& conn->ssl_in_use&& conn->allow_ssl_try	/* redundant? */&& !conn->wait_ssl_try) /* redundant? */{
						/* only retry once */
						conn->allow_ssl_try = false;
						need_new_connection = true;
						goto keep_going;
					}
#endif
					goto error_return;
				}
			
				conn->auth_req_received = true; /* It is an authentication request. 这是一个身份验证请求 */
				/* Get the type of request. */
				if (pqGetInt((int *) &areq, 4, conn)){
					/* We'll come back when there are more data */
					return PGRES_POLLING_READING;
				}
				msgLength -= 4;

				/* Ensure the password salt is in the input buffer, if it's an MD5 request.  All the other authentication methods that contain extra data in the authentication request are only supported in protocol version 3, in which case we already read the whole message above. 如果是 MD5 请求，请确保密码 salt 在输入缓冲区中。 仅在协议版本 3 中支持在身份验证请求中包含额外数据的所有其他身份验证方法，在这种情况下，我们已经阅读了上面的整个消息 */
				if (areq == AUTH_REQ_MD5 && PG_PROTOCOL_MAJOR(conn->pversion) < 3){
					msgLength += 4;
					avail = conn->inEnd - conn->inCursor;
					if (avail < 4){
						/* Before returning, try to enlarge the input buffer if needed to hold the whole message; see notes in pqParseInput3. */
						if (pqCheckInBufferSpace(conn->inCursor + (size_t) 4, conn))
							goto error_return;
						/* We'll come back when there is more data */
						return PGRES_POLLING_READING;
					}
				}

				/* Process the rest of the authentication request message, and respond to it if necessary. Note that conn->pghost must be non-NULL if we are going to avoid the Kerberos code doing a hostname look-up. 处理其余的身份验证请求消息，并在必要时对其进行响应。 请注意，如果我们要避免 Kerberos 代码进行主机名查找，则 conn->pghost 必须为非 NULL */
				res = pg_fe_sendauth(areq, msgLength, conn);
				conn->errorMessage.len = strlen(conn->errorMessage.data);
				/* OK, we have processed the message; mark data consumed */
				conn->inStart = conn->inCursor;
				if (res != STATUS_OK) goto error_return;
				/* Just make sure that any data sent by pg_fe_sendauth is flushed out.  Although this theoretically could block, it really shouldn't since we don't send large auth responses. */
				if (pqFlush(conn)) goto error_return;
				if (areq == AUTH_REQ_OK){				
					conn->status = CONNECTION_AUTH_OK; /* We are done with authentication exchange */
					/* Set asyncStatus so that PQgetResult will think that what comes back next is the result of a query.  See below. */
					conn->asyncStatus = PGASYNC_BUSY;
				}				
				goto keep_going; /* Look to see if we have more data yet. */
			}
```
当认证完成时，后端会在认证应答信息后发送一些其他协议，来通知前端一些必要的参数，其中有：

类型为S的ParameterStatus，为一个key-value对
类型为K的BackendKeyData，这个描述了一个取消Key，主要用户在开始阶段时Cancel request需要的key值，用于在一个新建会话中中断另一个会话中阻塞操作。
类型为Z的ReadyForQuery，代表后端已经准备好开始一个数据请求了
以下代码来自于src/backend/tcop/postgres.c/PostgresMain函数
类型为S的ParameterStatus，为一个key-value对
```
/* Now all GUC states are fully set up.  Report them to client if appropriate. */
	BeginReportingGUCOptions();
	 | -- ReportGUCOption
	       | -- pq_beginmessage(&msgbuf, 'S');
	       | -- pq_sendstring(&msgbuf, record->name);
	       | -- pq_sendstring(&msgbuf, val);
	       | -- pq_endmessage(&msgbuf);
```

类型为K的BackendKeyData，这个描述了一个取消Key，主要用户在开始阶段时Cancel request需要的key值，用于在一个新建会话中中断另一个会话中阻塞操作
```
 // 发送类型为K的BackendKeyData
	/* Send this backend's cancellation info to the frontend. */
	if (whereToSendOutput == DestRemote) {
		StringInfoData buf;
		pq_beginmessage(&buf, 'K');
		pq_sendint32(&buf, (int32) MyProcPid);
		pq_sendint32(&buf, (int32) MyCancelKey);
		pq_endmessage(&buf);
		/* Need not flush since ReadyForQuery will do it. */
	}
```

类型为Z的ReadyForQuery，代表后端已经准备好开始一个数据请求了

```
for (;;) {
		/* At top of loop, reset extended-query-message flag, so that any errors encountered in "idle" state don't provoke skip. */
		doing_extended_query_message = false;
		/* Release storage left over from prior query cycle, and create a new query input buffer in the cleared MessageContext. */
		MemoryContextSwitchTo(MessageContext);
		MemoryContextResetAndDeleteChildren(MessageContext);
		initStringInfo(&input_message);
		/* Also consider releasing our catalog snapshot if any, so that it's not preventing advance of global xmin while we wait for the client. */
		InvalidateCatalogSnapshotConditionally();
		/* (1) If we've reached idle state, tell the frontend we're ready for a new query.	*/
		if (send_ready_for_query){
			if (IsAbortedTransactionBlockState()){
				set_ps_display("idle in transaction (aborted)", false);
				pgstat_report_activity(STATE_IDLEINTRANSACTION_ABORTED, NULL);				
				if (IdleInTransactionSessionTimeout > 0) { /* Start the idle-in-transaction timer */
					disable_idle_in_transaction_timeout = true;
					enable_timeout_after(IDLE_IN_TRANSACTION_SESSION_TIMEOUT,IdleInTransactionSessionTimeout);
				}
			}else if (IsTransactionOrTransactionBlock()){
				set_ps_display("idle in transaction", false);
				pgstat_report_activity(STATE_IDLEINTRANSACTION, NULL);			
				if (IdleInTransactionSessionTimeout > 0){ /* Start the idle-in-transaction timer */
					disable_idle_in_transaction_timeout = true;
					enable_timeout_after(IDLE_IN_TRANSACTION_SESSION_TIMEOUT,IdleInTransactionSessionTimeout);
				}
			}else{			
				ProcessCompletedNotifies(); /* Send out notify signals and transmit self-notifies */
				if (notifyInterruptPending) ProcessNotifyInterrupt();
				pgstat_report_stat(false);
				set_ps_display("idle", false);
				pgstat_report_activity(STATE_IDLE, NULL);
			}
			ReadyForQuery(whereToSendOutput);
			send_ready_for_query = false;
		}
		/* (2) Allow asynchronous signals to be executed immediately if they come in while we are waiting for client input. (This must be conditional since we don't want, say, reads on behalf of COPY FROM STDIN doing the same thing.) */
		DoingCommandRead = true;		
		firstchar = ReadCommand(&input_message);	 /* (3) read a command (loop blocks here) */	
```

```
void ReadyForQuery(CommandDest dest) {
	switch (dest) {
		case DestRemote:
		case DestRemoteExecute:
		case DestRemoteSimple:
			if (PG_PROTOCOL_MAJOR(FrontendProtocol) >= 3) {
				StringInfoData buf;
				pq_beginmessage(&buf, 'Z');
				pq_sendbyte(&buf, TransactionBlockStatusCode());
				pq_endmessage(&buf);
			}else pq_putemptymessage('Z');
			/* Flush output at end of cycle in any case. */
			pq_flush();
			break;
		case DestNone:
		case DestDebug:
		case DestSPI:
		case DestTuplestore:
		case DestIntoRel:
		case DestCopyOut:
		case DestSQLFunction:
		case DestTransientRel:
		case DestTupleQueue:
			break;
	}
}
 
```

客户端尝试为此连接推进状态机，为CONNECTION_AUTH_OK状态进行处理。现在我们希望听到来自后端的消息。 ReadyForQuery 消息表明启动成功，但我们也可能会收到表明失败的错误消息。 （协议也允许指示非致命警告的通知消息，ParameterStatus 和 BackendKeyData 消息也是如此。）处理此问题的最简单方法是让 PQgetResult() 读取消息。 我们只需要通过设置 asyncStatus = PGASYNC_BUSY 来伪造连接状态。
```
	case CONNECTION_AUTH_OK: {
				/* Now we expect to hear from the backend. A ReadyForQuery
				 * message indicates that startup is successful, but we might
				 * also get an Error message indicating failure. (Notice
				 * messages indicating nonfatal warnings are also allowed by
				 * the protocol, as are ParameterStatus and BackendKeyData
				 * messages.) Easiest way to handle this is to let
				 * PQgetResult() read the messages. We just have to fake it
				 * out about the state of the connection, by setting
				 * asyncStatus = PGASYNC_BUSY (done above). */
				if (PQisBusy(conn)) return PGRES_POLLING_READING;
				res = PQgetResult(conn);
				/* NULL return indicating we have gone to IDLE state is expected */
				if (res){
					if (res->resultStatus != PGRES_FATAL_ERROR)
						appendPQExpBufferStr(&conn->errorMessage, libpq_gettext("unexpected message from server during startup\n"));
					else if (conn->send_appname && (conn->appname || conn->fbappname)){
						/* If we tried to send application_name, check to see
						 * if the error is about that --- pre-9.0 servers will
						 * reject it at this stage of the process.  If so,
						 * close the connection and retry without sending
						 * application_name.  We could possibly get a false
						 * SQLSTATE match here and retry uselessly, but there
						 * seems no great harm in that; we'll just get the
						 * same error again if it's unrelated. */ 如果我们尝试发送 application_name，请检查错误是否与此有关 --- 9.0 之前的服务器将在该过程的这个阶段拒绝它。 如果是这样，请关闭连接并重试而不发送 application_name。 我们可能会在这里得到一个错误的 SQLSTATE 匹配并无用地重试，但这似乎没有太大的危害； 如果它不相关，我们将再次收到相同的错误。
						const char *sqlstate;
						sqlstate = PQresultErrorField(res, PG_DIAG_SQLSTATE);
						if (sqlstate &&strcmp(sqlstate, ERRCODE_APPNAME_UNKNOWN) == 0){
							PQclear(res);
							conn->send_appname = false;
							need_new_connection = true;
							goto keep_going;
						}
					}

					/* if the resultStatus is FATAL, then conn->errorMessage
					 * already has a copy of the error; needn't copy it back.
					 * But add a newline if it's not there already, since
					 * postmaster error messages may not have one.
					 */
					if (conn->errorMessage.len <= 0 || conn->errorMessage.data[conn->errorMessage.len - 1] != '\n')
						appendPQExpBufferChar(&conn->errorMessage, '\n');
					PQclear(res);
					goto error_return;
				}

				/* Fire up post-connection housekeeping if needed */
				if (PG_PROTOCOL_MAJOR(conn->pversion) < 3){
					conn->status = CONNECTION_SETENV;
					conn->setenv_state = SETENV_STATE_CLIENT_ENCODING_SEND;
					conn->next_eo = EnvironmentOptions;
					return PGRES_POLLING_WRITING;
				}

				/* If a read-write connection is required, see if we have one.
				 * Servers before 7.4 lack the transaction_read_only GUC, but
				 * by the same token they don't have any read-only mode, so we
				 * may just skip the test in that case. 如果需要读写连接，看看我们有没有。 7.4 之前的服务器缺少 transaction_read_only GUC，但同样的，它们没有任何只读模式，所以在这种情况下我们可以跳过测试。*/
				if (conn->sversion >= 70400 && conn->target_session_attrs != NULL && strcmp(conn->target_session_attrs, "read-write") == 0) {
					/* Save existing error messages across the PQsendQuery attempt.  This is necessary because PQsendQuery is going to reset conn->errorMessage, so we would lose error messages related to previous hosts we have tried and failed to connect to. */
					if (!saveErrorMessage(conn, &savedMessage)) goto error_return;
					conn->status = CONNECTION_OK;
					if (!PQsendQuery(conn, "SHOW transaction_read_only")) {
						restoreErrorMessage(conn, &savedMessage);
						goto error_return;
					}
					conn->status = CONNECTION_CHECK_WRITABLE;
					restoreErrorMessage(conn, &savedMessage);
					return PGRES_POLLING_READING;
				}			
				release_conn_addrinfo(conn); /* We can release the address list now. */
				/* We are open for business! */
				conn->status = CONNECTION_OK;
				return PGRES_POLLING_OK;
			}
```