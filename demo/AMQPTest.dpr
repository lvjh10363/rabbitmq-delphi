program AMQPTest;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Net.Winsock2,
  amqp.connection in 'amqp.connection.pas',
  amqp.framing in 'amqp.framing.pas',
  AMQP.Types in 'AMQP.Types.pas',
  amqp.time in 'amqp.time.pas',
  amqp.socket in 'amqp.socket.pas',
  amqp.privt in 'amqp.privt.pas',
  amqp.table in 'amqp.table.pas',
  amqp.mem in 'amqp.mem.pas',
  amqp.tcp_socket in 'amqp.tcp_socket.pas',
  amqp.api in 'amqp.api.pas',
  MyFunc in 'MyFunc.pas',
  amqp.consumer in 'amqp.consumer.pas';

{var MyEnum : TMyEnum;
begin

  MyEnum := Two;
  writeln(Ord(MyEnum));  // writes 1, because first element in enumeration is numbered zero

  MyEnum := TMyEnum(2);  // Use TMyEnum as if it were a function
  Writeln (GetEnumName(TypeInfo(TMyEnum), Ord(MyEnum)));  //  Use RTTI to return the enum value's name
  readln;

end. }

function main:integer;
var
  port, status : integer;
  ret : Tamqp_rpc_reply;
  socket : Pamqp_socket;
  conn : Pamqp_connection_state;
  props : Tamqp_basic_properties;
  host: Ansistring;
  hostname, exchange, queue, routingkey, messagebody: PAMQPChar;
  tval: Ttimeval ;
  tv: Ptimeval ;
  vl: Tva_list;
  frame: Tamqp_frame;
  recv_queue_name: Tamqp_bytes;
  envelope: Tamqp_envelope;
  err: string;
begin
  socket := nil;

  if ( ParamCount > 0 ) then
    host := ParamStr(1)
  else
    Exit;

  hostname    := @host[1];
  port        := 5672;
  exchange    := 'Test.EX';
  queue       := 'Test.Q';
  routingkey     := 'test-key';
  messagebody := 'hello';
  
  if initializeWinsockIfNecessary() < 1 then
  begin
    Writeln('Failed to initialize "winsock": ');
    Exit;
  end;

  conn := amqp_new_connection();
  socket := amqp_tcp_socket_new(conn);
  if  socket = nil then begin
    Writeln('creating TCP socket failed!');
    Exit;
  end;

  var res := amqp_socket_open(socket, hostname, port);
  if res < 0 then
     Exit;

  vl.username := 'sa';
  vl.password := 'admin';
  vl.identity := '';
  die_on_amqp_error(amqp_login(conn, '/', 0, 131072, 0, AMQP_SASL_METHOD_PLAIN, vl),
                     'Logging in');



   amqp_channel_open(conn, 1);
   die_on_amqp_error(amqp_get_rpc_reply(conn), 'Opening channel');


    //���ն��У��˴�����������Ϣ
    recv_queue_name.len := Length(queue);
    recv_queue_name.bytes := PByte(queue);

    {
      consume
      2. ������Ϣ
    }

    amqp_basic_consume(conn, 1, recv_queue_name, amqp_empty_bytes, 0, 1, 0,
      amqp_empty_table);
    die_on_amqp_error(amqp_get_rpc_reply(conn), 'Consuming');
    {
      Get MSG
      3. ��ȡ��Ϣ�ľ�������
    }
    begin
      while True do
      begin
        amqp_maybe_release_buffers(conn);
        ret := amqp_consume_message(conn, @envelope, nil, 0);
        if AMQP_RESPONSE_NORMAL <> ret.reply_type then begin
          break;
        end;

        err := Format('Delivery %u, exchange %d %s routingkey %d %s\n',
                      [envelope.delivery_tag, envelope.exchange.len,
                      Pansichar(envelope.exchange.bytes), envelope.routing_key.len,
                      PAnsiChar(envelope.routing_key.bytes)]);
        Writeln('----');
        amqp_dump(envelope.message.body.bytes, envelope.message.body.len);
        {
          4. �˴�Ϊ���߸����޸Ĳ���
          ��Ϊ�ڷ��͵�ʱ���ʼ��propsΪ0�� ���������һ��RPC����Ϣ���ͣ���˴���reply_to�ĳ���Ӧ����0�����򣬲�Ϊ0
        }
        if 0 <> envelope.message.properties.reply_to.len then
        begin
          Writeln('there is a RPC reply');
          var reply_props :Tamqp_basic_properties;

          reply_props._flags := AMQP_BASIC_CONTENT_TYPE_FLAG or AMQP_BASIC_DELIVERY_MODE_FLAG;
          reply_props.content_type := amqp_cstring_bytes('text/plain');
          reply_props.delivery_mode := 2; { persistent delivery mode }
          reply_props.correlation_id := envelope.message.properties.correlation_id;
          {
            5. �ص���Ҫ�չ˵Ĳ���
            �˴�EXCHANGE_NAMEҲ���ǽ�����������Ϊ�գ������д���������ʹ�õ����ƣ�rpc client�˽������յ�������ʹ������������Ҳ����
            ��ԭ����Ҫд��ROUTE_KEY�Ĳ�������Ҫ������յ���reply_to��Ϣ��ֻ�е��������ֶ���д��ȷrpc client�Ż��յ��ظ�����Ϣ
          }
          var replyQ := PAnsiChar(envelope.message.properties.reply_to.bytes);
          die_on_error(amqp_basic_publish(conn, 1, amqp_cstring_bytes(''),
            amqp_cstring_bytes(replyQ), 0, 0,
            @reply_props, amqp_cstring_bytes(messagebody)),
            'Publishing');
        end;
        amqp_destroy_envelope(@envelope);
      end;
    end;
    die_on_amqp_error(amqp_channel_close(conn, 1, AMQP_REPLY_SUCCESS),
      'Closing channel');
    die_on_amqp_error(amqp_connection_close(conn, AMQP_REPLY_SUCCESS),
      'Closing connection');
    die_on_error(amqp_destroy_connection(conn), 'Ending connection');
    end;
end.



begin
  try
    Main;
  except
    on e:Exception do
      WriteLn(e.Message);
  end;
end.

