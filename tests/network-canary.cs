using System;
using System.Net;
using System.Net.Sockets;
class Canary {
 static bool Denied(string ip,int port,SocketType type,ProtocolType protocol){
  using(var s=new Socket(IPAddress.Parse(ip).AddressFamily,type,protocol)){
   try{s.Connect(new IPEndPoint(IPAddress.Parse(ip),port));if(type==SocketType.Dgram)s.Send(new byte[32]);return false;}
   catch(SocketException e){return e.SocketErrorCode==SocketError.AccessDenied;}
  }
 }
 static int Main(string[]args){
  bool allowed=false;using(var s=new TcpClient()){try{s.Connect(IPAddress.Loopback,int.Parse(args[0]));allowed=true;}catch{}}
  bool tcp4=Denied("192.0.2.99",443,SocketType.Stream,ProtocolType.Tcp),tcp6=Denied("::1",443,SocketType.Stream,ProtocolType.Tcp),udp=Denied("198.51.100.99",3478,SocketType.Dgram,ProtocolType.Udp),dns=Denied("192.0.2.53",53,SocketType.Dgram,ProtocolType.Udp),other=Denied("127.0.0.1",7892,SocketType.Stream,ProtocolType.Tcp);
  Console.WriteLine("{\"proxy_tcp_allowed\":"+allowed.ToString().ToLower()+",\"tcp4_wfp_denied\":"+tcp4.ToString().ToLower()+",\"tcp6_wfp_denied\":"+tcp6.ToString().ToLower()+",\"udp_wfp_denied\":"+udp.ToString().ToLower()+",\"raw_dns_wfp_denied\":"+dns.ToString().ToLower()+",\"other_loopback_port_wfp_denied\":"+other.ToString().ToLower()+"}");
  // UDP send return values do not prove delivery. The WFP observer supplies actual packet drop evidence.
  return allowed&&tcp4&&tcp6&&other?0:1;
 }
}
