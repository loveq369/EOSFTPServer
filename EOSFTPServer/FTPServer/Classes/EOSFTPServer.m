/*******************************************************************************
 * Copyright (c) 2012, Jean-David Gadina <macmade@eosgarden.com>
 * Distributed under the Boost Software License, Version 1.0.
 * 
 * Boost Software License - Version 1.0 - August 17th, 2003
 * 
 * Permission is hereby granted, free of charge, to any person or organization
 * obtaining a copy of the software and accompanying documentation covered by
 * this license (the "Software") to use, reproduce, display, distribute,
 * execute, and transmit the Software, and to prepare derivative works of the
 * Software, and to permit third-parties to whom the Software is furnished to
 * do so, all subject to the following:
 * 
 * The copyright notices in the Software and this entire statement, including
 * the above license grant, this restriction and the following disclaimer,
 * must be included in all copies of the Software, in whole or in part, and
 * all derivative works of the Software, unless such copies or derivative
 * works are solely in the form of machine-executable object code generated by
 * a source language processor.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
 * FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 ******************************************************************************/

/* $Id$ */

/*!
 * @file            ...
 * @author          Jean-David Gadina <macmade@eosgarden>
 * @copyright       (c) 2012, eosgarden
 * @abstract        ...
 */

#import "EOSFTPServer.h"
#import "EOSFTPServer+Private.h"
#import "EOSFTPServer+AsyncSocketDelegate.h"
#import "EOSFTPServer+Commands.h"
#import "EOSFTPServerUser.h"
#import "EOSFTPServerConnection.h"
#import "NSString+EOS.h"
#import "AsyncSocket.h"

NSString * const EOSFTPServerException = @"EOSFTPServerException";

EOSFTPServerCommand EOSFTPServerCommandUSER = @"USER";
EOSFTPServerCommand EOSFTPServerCommandPASS = @"PASS";
EOSFTPServerCommand EOSFTPServerCommandACT  = @"ACT";
EOSFTPServerCommand EOSFTPServerCommandCWD  = @"CWD";
EOSFTPServerCommand EOSFTPServerCommandCDUP = @"CDUP";
EOSFTPServerCommand EOSFTPServerCommandSMNT = @"SMNT";
EOSFTPServerCommand EOSFTPServerCommandREIN = @"REIN";
EOSFTPServerCommand EOSFTPServerCommandQUIT = @"QUIT";
EOSFTPServerCommand EOSFTPServerCommandPORT = @"PORT";
EOSFTPServerCommand EOSFTPServerCommandPASV = @"PASV";
EOSFTPServerCommand EOSFTPServerCommandTYPE = @"TYPE";
EOSFTPServerCommand EOSFTPServerCommandSTRU = @"STRU";
EOSFTPServerCommand EOSFTPServerCommandMODE = @"MODE";
EOSFTPServerCommand EOSFTPServerCommandRETR = @"RETR";
EOSFTPServerCommand EOSFTPServerCommandSTOR = @"STOR";
EOSFTPServerCommand EOSFTPServerCommandSTOU = @"STOU";
EOSFTPServerCommand EOSFTPServerCommandAPPE = @"APPE";
EOSFTPServerCommand EOSFTPServerCommandALLO = @"ALLO";
EOSFTPServerCommand EOSFTPServerCommandREST = @"REST";
EOSFTPServerCommand EOSFTPServerCommandRNFR = @"RNFR";
EOSFTPServerCommand EOSFTPServerCommandRNTO = @"RNTO";
EOSFTPServerCommand EOSFTPServerCommandABOR = @"ABOR";
EOSFTPServerCommand EOSFTPServerCommandDELE = @"DELE";
EOSFTPServerCommand EOSFTPServerCommandRMD  = @"RMD";
EOSFTPServerCommand EOSFTPServerCommandMKD  = @"MKD";
EOSFTPServerCommand EOSFTPServerCommandPWD  = @"PWD";
EOSFTPServerCommand EOSFTPServerCommandLIST = @"LIST";
EOSFTPServerCommand EOSFTPServerCommandNLST = @"NLST";
EOSFTPServerCommand EOSFTPServerCommandSITE = @"SITE";
EOSFTPServerCommand EOSFTPServerCommandSYST = @"SYST";
EOSFTPServerCommand EOSFTPServerCommandSTAT = @"STAT";
EOSFTPServerCommand EOSFTPServerCommandHELP = @"HELP";
EOSFTPServerCommand EOSFTPServerCommandNOOP = @"NOOP";

@implementation EOSFTPServer

@synthesize port                = _port;
@synthesize maxConnections      = _maxConnections;
@synthesize running             = _running;
@synthesize startDate           = _startDate;
@synthesize name                = _name;
@synthesize versionString       = _versionString;
@synthesize welcomeMessage      = _welcomeMessage;
@synthesize quitMessage         = _quitMessage;
@synthesize chroot              = _chroot;
@synthesize rootDirectory       = _rootDirectory;
@synthesize allowAnonymousUsers = _allowAnonymousUsers;
@synthesize encoding            = _encoding;
@synthesize delegate            = _delegate;

- ( id )init
{
    if( ( self = [ self initWithPort: 21 ] ) )
    {}
    
    return self;
}

- ( id )initWithPort: ( NSUInteger )port
{
    if( ( self = [ super init ] ) )
    {
        if( getuid() != 0 && port <= 1024 )
        {
            @throw [ NSException exceptionWithName: EOSFTPServerException reason: [ NSString stringWithFormat: @"Port number %u requires root privileges", port ] userInfo: nil ];
        }
        
        _port               = port;
        _name               = @"EOSFTPServer";
        _versionString      = @"0.1.0-alpha";
        _welcomeMessage     = @"Welcome to the EOSFTPServer.";
        _quitMessage        = @"Thank you for using the EOSFTPServer. Good bye!";
        _users              = [ [ NSMutableArray arrayWithCapacity: 100 ] retain ];
        _rootDirectory      = @"/";
        _connections        = [ [ NSMutableArray alloc ] initWithCapacity: 10 ];
        _connectedSockets   = [ [ NSMutableArray alloc ] initWithCapacity: 10 ];
        _listenSocket       = [ [ AsyncSocket alloc ] initWithDelegate: self ];
        _encoding           = NSUTF8StringEncoding;
    }
    
    return self;
}

- ( void )dealloc
{
    if( _listenSocket != nil )
    {
        [ _listenSocket disconnect ];
    }
    
    if( _netService != nil )
    {
        [ _netService stop ];
    }
    
    [ _startDate        release ];
    [ _name             release ];
    [ _versionString    release ];
    [ _welcomeMessage   release ];
    [ _quitMessage      release ];
    [ _users            release ];
    [ _rootDirectory    release ];
    [ _connections      release ];
    [ _connectedSockets release ];
    [ _listenSocket     release ];
    [ _netService       release ];
    
    [ super dealloc ];
}

- ( BOOL )start
{
    NSError * e;
    
    @synchronized( self )
    {
        if( _running == YES )
        {
            return YES;
        }
        
        if( _rootDirectory.length == 0 )
        {
            @throw [ NSException exceptionWithName: EOSFTPServerException reason: [ NSString stringWithFormat: @"No root directory set" ] userInfo: nil ];
        }
        
        [ _startDate release ];
        
        _startDate = [ [ NSDate date ] retain ];
        _running   = YES;
        e          = nil;
        
        [ _listenSocket acceptOnPort: ( UInt16 )_port error: &e ];
        
        _netService = [ [ NSNetService alloc ] initWithDomain: @"" type: @"_ftp._tcp." name: _name port: ( int )_port ];
        
        [ _netService publish ];
        
        if( e != nil )
        {
            return NO;
        }
        
        EOS_FTP_DEBUG( @"Server now listening on port %lu", _port );
        
        return YES;
    }
}

- ( BOOL )stop
{
    @synchronized( self )
    {
        if( _running == NO )
        {
            return YES;
        }
        
        if( _listenSocket != nil )
        {
            [ _listenSocket disconnect ];
        }
        
        if( _netService != nil )
        {
            [ _netService stop ];
            [ _netService release ];
            
            _netService = nil;
        }
        
        [ _connectedSockets removeAllObjects ];
        [ _connections      removeAllObjects ];
        
        [ _startDate release ];
        
        _startDate = nil;
        _running   = NO;
        
        EOS_FTP_DEBUG( @"Server stopped" );
        
        return YES;
    }
}

- ( BOOL )restart
{
    @synchronized( self )
    {
        if( _running == NO )
        {
            return [ self start ];
        }
        
        if( [ self stop ] == NO )
        {
            return NO;
        }
        
        return [ self start ];
    }
}

- ( void )addUser: ( EOSFTPServerUser * )user
{
    EOSFTPServerUser * u;
    
    @synchronized( self )
    {
        for( u in _users )
        {
            if( [ user isEqual: u ] == YES )
            {
                return;
            }
        }
        
        [ _users addObject: user ];
    }
}

- ( BOOL )userIsConnected: ( EOSFTPServerUser * )user
{
    EOSFTPServerUser * u;
    
    for( u in _users )
    {
        if( [ user isEqual: u ] == YES )
        {
            return YES;
        }
    }
    
    return NO;
}

- ( BOOL )userCanLogin: ( NSString * )username
{
    EOSFTPServerUser * u;
    
    if( [ username isEqualToString: @"anonymous" ] == YES && _allowAnonymousUsers == YES )
    {
        return YES;
    }
    
    for( u in _users )
    {
        if( [ u.name isEqualToString: username ] )
        {
            return YES;
        }
    }
    
    return NO;
}

- ( BOOL )authenticateUser: ( EOSFTPServerUser * )user
{
    NSString         * md5Password;
    EOSFTPServerUser * u;
    
    if( user.md5Password.length != 0 )
    {
        md5Password = user.md5Password;
    }
    else if( user.password.length != 0 )
    {
        md5Password = [ user.password md5Hash ];
    }
    else
    {
        md5Password = nil;
    }
    
    for( u in _users )
    {
        if( [ u.name isEqualToString: user.name ] )
        {
            if( u.md5Password.length == 0 && u.password.length == 0 && md5Password.length == 0 )
            {
                return YES;
            }
            else if( u.md5Password.length > 0 && [ u.md5Password isEqualToString: md5Password ] == YES )
            {
                return YES;
            }
            else if( u.password.length > 0 && [ [ u.password md5Hash ] isEqualToString: md5Password ] )
            {
                return YES;
            }
        }
    }
    
    return NO;
}

- ( NSArray * )connectedUsers
{
    @synchronized( self )
    {
        return [ NSArray arrayWithArray: _users ];
    }
}

- ( NSString * )helpForCommand: ( NSString * )command
{
    NSString * help;
    
    command = [ command uppercaseString ];
    
    if( [ command isEqualToString: EOSFTPServerCommandUSER ] )
    {
        help =  @"USER NAME (USER)\n"
                @"\n"
                @"The argument field is a Telnet string identifying the user.\n"
                @"The user identification is that which is required by the\n"
                @"server for access to its file system. This command will\n"
                @"normally be the first command transmitted by the user after\n"
                @"the control connections are made (some servers may require\n"
                @"this). Additional identification information in the form of\n"
                @"a password and/or an account command may also be required by\n"
                @"some servers. Servers may allow a new USER command to be\n"
                @"entered at any point in order to change the access control\n"
                @"and/or accounting information. This has the effect of\n"
                @"flushing any user, password, and account information already\n"
                @"supplied and beginning the login sequence again. All\n"
                @"transfer parameters are unchanged and any file transfer in\n"
                @"progress is completed under the old access control\n"
                @"parameters.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandPASS ] )
    {
        help =  @"PASSWORD (PASS)\n"
                @"\n"
                @"The argument field is a Telnet string specifying the user's\n"
                @"password. This command must be immediately preceded by the\n"
                @"user name command, and, for some sites, completes the user's\n"
                @"identification for access control. Since password\n"
                @"information is quite sensitive, it is desirable in general\n"
                @"to \"mask\" it or suppress typeout. It appears that the\n"
                @"server has no foolproof way to achieve this. It is\n"
                @"therefore the responsibility of the user-FTP process to hide\n"
                @"the sensitive password information.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandACT ] )
    {
        help  = @"ACCOUNT (ACCT)\n"
                @"\n"
                @"The argument field is a Telnet string identifying the user's\n"
                @"account. The command is not necessarily related to the USER\n"
                @"command, as some sites may require an account for login and\n"
                @"others only for specific access, such as storing files. In\n"
                @"the latter case the command may arrive at any time.\n"
                @"\n"
                @"There are reply codes to differentiate these cases for the\n"
                @"automation: when account information is required for login,\n"
                @"the response to a successful PASSword command is reply code\n"
                @"332. On the other hand, if account information is NOT\n"
                @"required for login, the reply to a successful PASSword\n"
                @"command is 230; and if the account information is needed for\n"
                @"a command issued later in the dialogue, the server should\n"
                @"return a 332 or 532 reply depending on whether it stores\n"
                @"(pending receipt of the ACCounT command) or discards the\n"
                @"command, respectively.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandCWD ] )
    {
        help  = @"CHANGE WORKING DIRECTORY (CWD)\n"
                @"\n"
                @"This command allows the user to work with a different\n"
                @"directory or dataset for file storage or retrieval without\n"
                @"altering his login or accounting information. Transfer\n"
                @"parameters are similarly unchanged. The argument is a\n"
                @"pathname specifying a directory or other system dependent\n"
                @"file group designator.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandCDUP ] )
    {
        help  = @"CHANGE TO PARENT DIRECTORY (CDUP)\n"
                @"\n"
                @"This command is a special case of CWD, and is included to\n"
                @"simplify the implementation of programs for transferring\n"
                @"directory trees between operating systems having different\n"
                @"syntaxes for naming the parent directory. The reply codes\n"
                @"shall be identical to the reply codes of CWD.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandSMNT ] )
    {
        help  = @"STRUCTURE MOUNT (SMNT)\n"
                @"\n"
                @"This command allows the user to mount a different file\n"
                @"system data structure without altering his login or\n"
                @"accounting information. Transfer parameters are similarly\n"
                @"unchanged. The argument is a pathname specifying a\n"
                @"directory or other system dependent file group designator.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandREIN ] )
    {
        help  = @"REINITIALIZE (REIN)\n"
                @"\n"
                @"This command terminates a USER, flushing all I/O and account\n"
                @"information, except to allow any transfer in progress to be\n"
                @"completed. All parameters are reset to the default settings\n"
                @"and the control connection is left open. This is identical\n"
                @"to the state in which a user finds himself immediately after\n"
                @"the control connection is opened. A USER command may be\n"
                @"expected to follow.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandQUIT ] )
    {
        help  = @"LOGOUT (QUIT)\n"
                @"\n"
                @"This command terminates a USER and if file transfer is not\n"
                @"in progress, the server closes the control connection. If\n"
                @"file transfer is in progress, the connection will remain\n"
                @"open for result response and the server will then close it.\n"
                @"If the user-process is transferring files for several USERs\n"
                @"but does not wish to close and then reopen connections for\n"
                @"each, then the REIN command should be used instead of QUIT.\n"
                @"\n"
                @"An unexpected close on the control connection will cause the\n"
                @"server to take the effective action of an abort (ABOR) and a\n"
                @"logout (QUIT).\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandPORT ] )
    {
        help  = @"DATA PORT (PORT)\n"
                @"\n"
                @"The argument is a HOST-PORT specification for the data port\n"
                @"to be used in data connection. There are defaults for both\n"
                @"the user and server data ports, and under normal\n"
                @"circumstances this command and its reply are not needed. If\n"
                @"this command is used, the argument is the concatenation of a\n"
                @"32-bit internet host address and a 16-bit TCP port address.\n"
                @"This address information is broken into 8-bit fields and the\n"
                @"value of each field is transmitted as a decimal number (in\n"
                @"character string representation). The fields are separated\n"
                @"by commas. A port command would be:\n"
                @"\n"
                @"PORT h1,h2,h3,h4,p1,p2\n"
                @"\n"
                @"where h1 is the high order 8 bits of the internet host\n"
                @"address.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandPASV ] )
    {
        help  = @"PASSIVE (PASV)\n"
                @"\n"
                @"This command requests the server-DTP to \"listen\" on a data\n"
                @"port (which is not its default data port) and to wait for a\n"
                @"connection rather than initiate one upon receipt of a\n"
                @"transfer command. The response to this command includes the\n"
                @"host and port address this server is listening on.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandTYPE ] )
    {
        help  = @"REPRESENTATION TYPE (TYPE)\n"
                @"\n"
                @"The argument specifies the representation type as described\n"
                @"in the Section on Data Representation and Storage. Several\n"
                @"types take a second parameter. The first parameter is\n"
                @"denoted by a single Telnet character, as is the second\n"
                @"Format parameter for ASCII and EBCDIC; the second parameter\n"
                @"for local byte is a decimal integer to indicate Bytesize.\n"
                @"The parameters are separated by a <SP> (Space, ASCII code\n"
                @"32).\n"
                @"\n"
                @"The following codes are assigned for type:\n"
                @"\n"
                @" \\    /\n"
                @"A - ASCII |    | N - Non-print\n"
                @" |-><-| T - Telnet format effectors\n"
                @"E - EBCDIC|    | C - Carriage Control (ASA)\n"
                @" /    \\n"
                @"I - Image\n"
                @"\n"
                @"L <byte size> - Local byte Byte size\n"
                @"\n"
                @"The default representation type is ASCII Non-print. If the\n"
                @"Format parameter is changed, and later just the first\n"
                @"argument is changed, Format then returns to the Non-print\n"
                @"default.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandSTRU ] )
    {
        help  = @"FILE STRUCTURE (STRU)\n"
                @"\n"
                @"The argument is a single Telnet character code specifying\n"
                @"file structure described in the Section on Data\n"
                @"Representation and Storage.\n"
                @"\n"
                @"The following codes are assigned for structure:\n"
                @"\n"
                @"F - File (no record structure)\n"
                @"R - Record structure\n"
                @"P - Page structure\n"
                @"\n"
                @"The default structure is File.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandMODE ] )
    {
        help  = @"TRANSFER MODE (MODE)\n"
                @"\n"
                @"The argument is a single Telnet character code specifying\n"
                @"the data transfer modes described in the Section on\n"
                @"Transmission Modes.\n"
                @"\n"
                @"The following codes are assigned for transfer modes:\n"
                @"\n"
                @"S - Stream\n"
                @"B - Block\n"
                @"C - Compressed\n"
                @"\n"
                @"The default transfer mode is Stream.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandRETR ] )
    {
        help  = @"RETRIEVE (RETR)\n"
                @"\n"
                @"This command causes the server-DTP to transfer a copy of the\n"
                @"file, specified in the pathname, to the server- or user-DTP\n"
                @"at the other end of the data connection. The status and\n"
                @"contents of the file at the server site shall be unaffected.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandSTOR ] )
    {
        help  = @"STORE (STOR)\n"
                @"\n"
                @"This command causes the server-DTP to accept the data\n"
                @"transferred via the data connection and to store the data as\n"
                @"a file at the server site. If the file specified in the\n"
                @"pathname exists at the server site, then its contents shall\n"
                @"be replaced by the data being transferred. A new file is\n"
                @"created at the server site if the file specified in the\n"
                @"pathname does not already exist.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandSTOU ] )
    {
        help  = @"STORE UNIQUE (STOU)\n"
                @"\n"
                @"This command behaves like STOR except that the resultant\n"
                @"file is to be created in the current directory under a name\n"
                @"unique to that directory. The 250 Transfer Started response\n"
                @"must include the name generated.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandAPPE ] )
    {
        help  = @"APPEND (with create) (APPE)\n"
                @"\n"
                @"This command causes the server-DTP to accept the data\n"
                @"transferred via the data connection and to store the data in\n"
                @"a file at the server site. If the file specified in the\n"
                @"pathname exists at the server site, then the data shall be\n"
                @"appended to that file; otherwise the file specified in the\n"
                @"pathname shall be created at the server site.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandALLO ] )
    {
        help  = @"ALLOCATE (ALLO)\n"
                @"\n"
                @"This command may be required by some servers to reserve\n"
                @"sufficient storage to accommodate the new file to be\n"
                @"transferred. The argument shall be a decimal integer\n"
                @"representing the number of bytes (using the logical byte\n"
                @"size) of storage to be reserved for the file. For files\n"
                @"sent with record or page structure a maximum record or page\n"
                @"size (in logical bytes) might also be necessary; this is\n"
                @"indicated by a decimal integer in a second argument field of\n"
                @"the command. This second argument is optional, but when\n"
                @"present should be separated from the first by the three\n"
                @"Telnet characters <SP> R <SP>. This command shall be\n"
                @"followed by a STORe or APPEnd command. The ALLO command\n"
                @"should be treated as a NOOP (no operation) by those servers\n"
                @"which do not require that the maximum size of the file be\n"
                @"declared beforehand, and those servers interested in only\n"
                @"the maximum record or page size should accept a dummy value\n"
                @"in the first argument and ignore it.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandREST ] )
    {
        help  = @"RESTART (REST)\n"
                @"\n"
                @"The argument field represents the server marker at which\n"
                @"file transfer is to be restarted. This command does not\n"
                @"cause file transfer but skips over the file to the specified\n"
                @"data checkpoint. This command shall be immediately followed\n"
                @"by the appropriate FTP service command which shall cause\n"
                @"file transfer to resume.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandRNFR ] )
    {
        help  = @"RENAME FROM (RNFR)\n"
                @"\n"
                @"This command specifies the old pathname of the file which is\n"
                @"to be renamed. This command must be immediately followed by\n"
                @"a \"rename to\" command specifying the new file pathname.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandRNTO ] )
    {
        help  = @"RENAME TO (RNTO)\n"
                @"\n"
                @"This command specifies the new pathname of the file\n"
                @"specified in the immediately preceding \"rename from\"\n"
                @"command. Together the two commands cause a file to be\n"
                @"renamed.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandABOR ] )
    {
        help  = @"ABORT (ABOR)\n"
                @"\n"
                @"This command tells the server to abort the previous FTP\n"
                @"service command and any associated transfer of data. The\n"
                @"abort command may require \"special action\", as discussed in\n"
                @"the Section on FTP Commands, to force recognition by the\n"
                @"server. No action is to be taken if the previous command\n"
                @"has been completed (including data transfer). The control\n"
                @"connection is not to be closed by the server, but the data\n"
                @"connection must be closed.\n"
                @"\n"
                @"There are two cases for the server upon receipt of this\n"
                @"command: (1) the FTP service command was already completed,\n"
                @"or (2) the FTP service command is still in progress.\n"
                @"\n"
                @"In the first case, the server closes the data connection\n"
                @"(if it is open) and responds with a 226 reply, indicating\n"
                @"that the abort command was successfully processed.\n"
                @"\n"
                @"In the second case, the server aborts the FTP service in\n"
                @"progress and closes the data connection, returning a 426\n"
                @"reply to indicate that the service request terminated\n"
                @"abnormally. The server then sends a 226 reply,\n"
                @"indicating that the abort command was successfully\n"
                @"processed.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandDELE ] )
    {
        help  = @"DELETE (DELE)\n"
                @"\n"
                @"This command causes the file specified in the pathname to be\n"
                @"deleted at the server site. If an extra level of protection\n"
                @"is desired (such as the query, \"Do you really wish to\n"
                @"delete?\"), it should be provided by the user-FTP process.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandRMD ] )
    {
        help  = @"REMOVE DIRECTORY (RMD)\n"
                @"\n"
                @"This command causes the directory specified in the pathname\n"
                @"to be removed as a directory (if the pathname is absolute)\n"
                @"or as a subdirectory of the current working directory (if\n"
                @"the pathname is relative).\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandMKD ] )
    {
        help  = @"MAKE DIRECTORY (MKD)\n"
                @"\n"
                @"This command causes the directory specified in the pathname\n"
                @"to be created as a directory (if the pathname is absolute)\n"
                @"or as a subdirectory of the current working directory (if\n"
                @"the pathname is relative).\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandPWD ] )
    {
        help  = @"PRINT WORKING DIRECTORY (PWD)\n"
                @"\n"
                @"This command causes the name of the current working\n"
                @"directory to be returned in the reply.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandLIST ] )
    {
        help  = @"LIST (LIST)\n"
                @"\n"
                @"This command causes a list to be sent from the server to the\n"
                @"passive DTP. If the pathname specifies a directory or other\n"
                @"group of files, the server should transfer a list of files\n"
                @"in the specified directory. If the pathname specifies a\n"
                @"file then the server should send current information on the\n"
                @"file. A null argument implies the user's current working or\n"
                @"default directory. The data transfer is over the data\n"
                @"connection in type ASCII or type EBCDIC. (The user must\n"
                @"ensure that the TYPE is appropriately ASCII or EBCDIC).\n"
                @"Since the information on a file may vary widely from system\n"
                @"to system, this information may be hard to use automatically\n"
                @"in a program, but may be quite useful to a human user.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandNLST ] )
    {
        help  = @"NAME LIST (NLST)\n"
                @"\n"
                @"This command causes a directory listing to be sent from\n"
                @"server to user site. The pathname should specify a\n"
                @"directory or other system-specific file group descriptor; a\n"
                @"null argument implies the current directory. The server\n"
                @"will return a stream of names of files and no other\n"
                @"information. The data will be transferred in ASCII or\n"
                @"EBCDIC type over the data connection as valid pathname\n"
                @"strings separated by <CRLF> or <NL>. (Again the user must\n"
                @"ensure that the TYPE is correct.) This command is intended\n"
                @"to return information that can be used by a program to\n"
                @"further process the files automatically. For example, in\n"
                @"the implementation of a \"multiple get\" function.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandSITE ] )
    {
        help  = @"SITE PARAMETERS (SITE)\n"
                @"\n"
                @"This command is used by the server to provide services\n"
                @"specific to his system that are essential to file transfer\n"
                @"but not sufficiently universal to be included as commands in\n"
                @"the protocol. The nature of these services and the\n"
                @"specification of their syntax can be stated in a reply to\n"
                @"the HELP SITE command.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandSYST ] )
    {
        help  = @"SYSTEM (SYST)\n"
                @"\n"
                @"This command is used to find out the type of operating\n"
                @"system at the server. The reply shall have as its first\n"
                @"word one of the system names listed in the current version\n"
                @"of the Assigned Numbers document.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandSTAT ] )
    {
        help  = @"STATUS (STAT)\n"
                @"\n"
                @"This command shall cause a status response to be sent over\n"
                @"the control connection in the form of a reply. The command\n"
                @"may be sent during a file transfer (along with the Telnet IP\n"
                @"and Synch signals--see the Section on FTP Commands) in which\n"
                @"case the server will respond with the status of the\n"
                @"operation in progress, or it may be sent between file\n"
                @"transfers. In the latter case, the command may have an\n"
                @"argument field. If the argument is a pathname, the command\n"
                @"is analogous to the \"list\" command except that data shall be\n"
                @"transferred over the control connection. If a partial\n"
                @"pathname is given, the server may respond with a list of\n"
                @"file names or attributes associated with that specification.\n"
                @"If no argument is given, the server should return general\n"
                @"status information about the server FTP process. This\n"
                @"should include current values of all transfer parameters and\n"
                @"the status of connections.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandHELP ] )
    {
        help  = @"HELP (HELP)\n"
                @"\n"
                @"This command shall cause the server to send helpful\n"
                @"information regarding its implementation status over the\n"
                @"control connection to the user. The command may take an\n"
                @"argument (e.g., any command name) and return more specific\n"
                @"information as a response. The reply is type 211 or 214.\n"
                @"It is suggested that HELP be allowed before entering a USER\n"
                @"command. The server may use this reply to specify\n"
                @"site-dependent parameters, e.g., in response to HELP SITE.\n";
    }
    else if( [ command isEqualToString: EOSFTPServerCommandNOOP ] )
    {
        help  = @"NOOP (NOOP)\n"
                @"\n"
                @"This command does not affect any parameters or previously\n"
                @"entered commands. It specifies no action other than that the\n"
                @"server send an OK reply.\n";
    }
    else
    {
        help = [ NSString stringWithFormat: @"%@\n"
                                            @"\n"
                                            @"No help available for this command.\n",
                                            command
               ];
    }
    
    return help;
}

- ( NSString * )messageForReplyCode: ( EOSFTPServerReplyCode )code
{
    switch( code )
    {
        case 120: return @"Service ready in %u minutes.";
        case 125: return @"Data connection already open; transfer starting.";
        case 150: return @"File status okay; about to open data connection.";
        case 200: return @"Command okay.";
        case 202: return @"Command not implemented, superfluous at this site.";
        case 211: return @"System status, or system help reply.";
        case 212: return @"Directory status.";
        case 213: return @"File status.";
        case 214: return @"%@";
        case 215: return @"%@ system type.";
        case 220: return @"Service ready for new user.";
        case 221: return @"Service closing control connection.";
        case 225: return @"Data connection open; no transfer in progress.";
        case 226: return @"Closing data connection. Requested file action successful (for example, file transfer or file abort).";
        case 227: return @"Entering Passive Mode (%u,%u,%u,%u,%u,%u).";
        case 230: return @"User logged in, proceed.";
        case 250: return @"Requested file action okay, completed.";
        case 257: return @"%@ created.";
        case 331: return @"User name okay, need password.";
        case 332: return @"Need account for login.";
        case 350: return @"Requested file action pending further information.";
        case 421: return @"Service not available, closing control connection.";
        case 425: return @"Can't open data connection.";
        case 426: return @"Connection closed; transfer aborted.";
        case 450: return @"Requested file action not taken. File unavailable (e.g., file busy).";
        case 451: return @"Requested action aborted: local error in processing.";
        case 452: return @"Requested action not taken. Insufficient storage space in system.";
        case 500: return @"Syntax error, command unrecognized.";
        case 501: return @"Syntax error in parameters or arguments.";
        case 502: return @"Command not implemented.";
        case 503: return @"Bad sequence of commands.";
        case 504: return @"Command not implemented for that parameter.";
        case 530: return @"Not logged in.";
        case 532: return @"Need account for storing files.";
        case 550: return @"Requested action not taken. File unavailable (e.g., file not found, no access).";
        case 551: return @"Requested action aborted: page type unknown.";
        case 552: return @"Requested file action aborted. Exceeded storage allocation (for current directory or dataset).";
        case 553: return @"Requested action not taken. File name not allowed.";
    }
    
    return nil;
}

- ( void )processCommand: ( NSString * )command connection: ( EOSFTPServerConnection * )connection
{
    NSRange    range;
    NSString * name;
    NSString * arguments;
    SEL        selector;
    
    range = [ command rangeOfString: @" " ];
    
    if( range.location != NSNotFound )
    {
        name      = [ command substringToIndex: range.location ];
        arguments = [ command substringFromIndex: range.location + 1 ];
    }
    else
    {
        name      = command;
        arguments = nil;
    }
    
    EOS_FTP_DEBUG( @"Processing command: %@ (%@)", name, arguments );
    
    selector = NSSelectorFromString( [ NSString stringWithFormat: @"processCommand%@:arguments:", [ name uppercaseString ] ] );
    
    if( selector != NULL && [ self respondsToSelector: selector ] )
    {
        [ self performSelector: selector withObject: connection withObject: arguments ];
    }
    else
    {
        [ self unrecognizedCommand: name connection: connection ];
    }
}

@end
