## PostgreSQL数据库网络层—pg_basebackup replication参数
replication此选项确定连接是否应使用复制协议而不是普通协议。 这是[PostgreSQL](https://so.csdn.net/so/search?q=PostgreSQL&spm=1001.2101.3001.7020) 复制连接以及 pg_basebackup 等工具在内部使用的内容，但第三方应用程序也可以使用它。 有关复制协议的描述，请参阅第 53.4 节。支持以下不区分大小写的值：

|  `参数值`   | 描述   |  
| :------------------: | :----------:    |  
| `true, on, yes, 1` |   The connection goes into physical replication mode.|  
| `database`       |    The connection goes into logical replication mode, connecting to the database specified in the dbname parameter.     |   
| `false, off, no, 0`       |    The connection is a regular one, which is the default behavior.|  


```
/* Connect to the server. Returns a valid PGconn pointer if connected, or NULL on non-permanent error. On permanent error, the function will call exit(1) directly. */
PGconn *GetConnection(void) {
	PGconn	   *tmpconn;
	int			argcount = 7;	/* dbname, replication, fallback_app_name, host, user, port, password */
	int			i;
	const char **keywords; const char **values; const char *tmpparam;
	bool		need_password;
	PQconninfoOption *conn_opts = NULL;
	PQconninfoOption *conn_opt;
	char	   *err_msg = NULL;
	
	Assert(dbname == NULL || connection_string == NULL); /* pg_recvlogical uses dbname only; others use connection_string only. */
```

合并以连接字符串、选项和默认值（dbname=replication、replication=true 等）形式给出的连接信息输入。显式丢弃连接字符串中的任何 dbname 值； 否则， PQconnectdbParams() 会将该值解释为本身就是一个连接字符串。
```
	/* Merge the connection info inputs given in form of connection string,
	 * options and default values (dbname=replication, replication=true, etc.)
	 * Explicitly discard any dbname value in the connection string;
	 * otherwise, PQconnectdbParams() would interpret that value as being
	 * itself a connection string. */
	i = 0;
	if (connection_string) {
		conn_opts = PQconninfoParse(connection_string, &err_msg);
		if (conn_opts == NULL) {
			pg_log_error("%s", err_msg); exit(1);
		}
		for (conn_opt = conn_opts; conn_opt->keyword != NULL; conn_opt++) {
			if (conn_opt->val != NULL && conn_opt->val[0] != '\0' && strcmp(conn_opt->keyword, "dbname") != 0) argcount++;
		}
		keywords = pg_malloc0((argcount + 1) * sizeof(*keywords));
		values = pg_malloc0((argcount + 1) * sizeof(*values));
		for (conn_opt = conn_opts; conn_opt->keyword != NULL; conn_opt++) {
			if (conn_opt->val != NULL && conn_opt->val[0] != '\0' && strcmp(conn_opt->keyword, "dbname") != 0){
				keywords[i] = conn_opt->keyword; values[i] = conn_opt->val; i++;
			}
		}
	}else{
		keywords = pg_malloc0((argcount + 1) * sizeof(*keywords));
		values = pg_malloc0((argcount + 1) * sizeof(*values));
	}

	keywords[i] = "dbname"; values[i] = dbname == NULL ? "replication" : dbname;  // 未指定dbname则直接使用replication
	i++;
	keywords[i] = "replication"; values[i] = dbname == NULL ? "true" : "database"; // 如果没有指定dbname则直接使用true，指定了则使用database
	i++;
	keywords[i] = "fallback_application_name"; values[i] = progname;
	i++;

	if (dbhost) {
		keywords[i] = "host"; values[i] = dbhost; i++;
	}
	if (dbuser) {
		keywords[i] = "user"; values[i] = dbuser; i++;
	}
	if (dbport) {
		keywords[i] = "port"; values[i] = dbport; i++;
	}	
	need_password = (dbgetpassword == 1 && !have_password); /* If -W was given, force prompt for password, but only the first time */

	do {		
		if (need_password) /* Get a new password if appropriate */ {
			simple_prompt("Password: ", password, sizeof(password), false);
			have_password = true; need_password = false;
		}	
		if (have_password) /* Use (or reuse, on a subsequent connection) password if we have it */ {
			keywords[i] = "password"; values[i] = password;
		} else {
			keywords[i] = NULL; values[i] = NULL;
		}
```
dbname变量未指定则dbname参数直接使用replication字符串
dbname变量未指定则replication直接使用true，指定了则使用database字符串

使用PQconnectdbParams API连接服务端。
```
		tmpconn = PQconnectdbParams(keywords, values, true);
		/* If there is too little memory even to allocate the PGconn object and PQconnectdbParams returns NULL, we call exit(1) directly. */
		if (!tmpconn) {
			pg_log_error("could not connect to server"); exit(1);
		}		
		if (PQstatus(tmpconn) == CONNECTION_BAD && PQconnectionNeedsPassword(tmpconn) && dbgetpassword != -1) { /* If we need a password and -w wasn't given, loop back and get one */
			PQfinish(tmpconn); need_password = true;
		}
	} while (need_password);

	if (PQstatus(tmpconn) != CONNECTION_OK) {
		pg_log_error("%s", PQerrorMessage(tmpconn));
		PQfinish(tmpconn);
		free(values);
		free(keywords);
		if (conn_opts) PQconninfoFree(conn_opts);
		return NULL;
	}
	/* Connection ok! */
	free(values); free(keywords);
	if (conn_opts) PQconninfoFree(conn_opts);
```

设置始终安全的搜索路径，使恶意用户无法控制。 在 PostgreSQL 10 中添加了运行普通 SQL 查询的能力，因此在早期版本中（我们或攻击者）无法更改搜索路径。
```
	/* Set always-secure search path, so malicious users can't get control.
	 * The capacity to run normal SQL queries was added in PostgreSQL 10, so
	 * the search path cannot be changed (by us or attackers) on earlier
	 * versions. */
	if (dbname != NULL && PQserverVersion(tmpconn) >= 100000) {
		PGresult   *res;
		res = PQexec(tmpconn, ALWAYS_SECURE_SEARCH_PATH_SQL);
		if (PQresultStatus(res) != PGRES_TUPLES_OK) {
			pg_log_error("could not clear search_path: %s", PQerrorMessage(tmpconn)); PQclear(res); PQfinish(tmpconn); exit(1);
		}
		PQclear(res);
	}

	/* Ensure we have the same value of integer_datetimes (now always "on") as the server we are connecting to. */
	tmpparam = PQparameterStatus(tmpconn, "integer_datetimes");
	if (!tmpparam) {
		pg_log_error("could not determine server setting for integer_datetimes");
		PQfinish(tmpconn);
		exit(1);
	}

	if (strcmp(tmpparam, "on") != 0) {
		pg_log_error("integer_datetimes compile flag does not match server");
		PQfinish(tmpconn);
		exit(1);
	}

	/* Retrieve the source data directory mode and use it to construct a umask for creating directories and files. */
	if (!RetrieveDataDirCreatePerm(tmpconn)) {
		PQfinish(tmpconn);
		exit(1);
	}

	return tmpconn;
}

```
RetrieveDataDirCreatePerm此函数用于确定服务器 PG 数据目录的权限，并在此基础上设置我们创建的目录和文件的权限。PG11 添加了对（可选）要在数据目录上设置的组读取/执行权限的支持。 在 PG11 之前，只允许所有者拥有数据目录的权限。
```
static bool RetrieveDataDirCreatePerm(PGconn *conn) {
	PGresult   *res;
	int			data_directory_mode;
	/* check connection existence */
	Assert(conn != NULL);
	/* for previous versions leave the default group access */
	if (PQserverVersion(conn) < MINIMUM_VERSION_FOR_GROUP_ACCESS) return true;

	res = PQexec(conn, "SHOW data_directory_mode");
	if (PQresultStatus(res) != PGRES_TUPLES_OK){
		pg_log_error("could not send replication command \"%s\": %s", "SHOW data_directory_mode", PQerrorMessage(conn));
		PQclear(res);
		return false;
	}
	if (PQntuples(res) != 1 || PQnfields(res) < 1) {
		pg_log_error("could not fetch group access flag: got %d rows and %d fields, expected %d rows and %d or more fields", PQntuples(res), PQnfields(res), 1, 1);
		PQclear(res);
		return false;
	}
	if (sscanf(PQgetvalue(res, 0, 0), "%o", &data_directory_mode) != 1) {
		pg_log_error("group access flag could not be parsed: %s", PQgetvalue(res, 0, 0)); PQclear(res); return false;
	}
	SetDataDirectoryCreatePerm(data_directory_mode);
	PQclear(res);
	return true;
}
```