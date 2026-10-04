using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Concurrent;

// File-only IPC for a guest with all virtual network adapters removed.
// Broker's only network destination is a numeric IPv4 loopback proxy.
class FileTunnel {
    const int Chunk=65536,Window=16,MaxSessions=16;
    static string root; static int proxyPort; static int running;
    static readonly ConcurrentDictionary<string,byte> sessions=new ConcurrentDictionary<string,byte>();
    static string SafeDirectory(string id) {
        Guid parsed;if(!Guid.TryParseExact(id,"N",out parsed))throw new IOException("Invalid session");
        string p=Path.Combine(root,id);
        if(Directory.Exists(p)&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new IOException("Reparse directory refused");
        return p;
    }
    static void Atomic(string p,byte[] data) {
        string tmp=p+".tmp";
        using(var f=new FileStream(tmp,FileMode.Create,FileAccess.Write,FileShare.None)){f.Write(data,0,data.Length);f.Flush(true);}
        File.Move(tmp,p);
    }
    static bool Closed(string p){return File.Exists(Path.Combine(p,"closed"));}
    static void Close(string p){try{File.WriteAllText(Path.Combine(p,"closed"),"closed");}catch{}}
    static void ToFiles(Stream stream,string dir,string prefix) {
        long index=0;byte[] buffer=new byte[Chunk];
        while(!Closed(dir)){
            int n=stream.Read(buffer,0,buffer.Length);if(n==0){Atomic(Path.Combine(dir,prefix+index.ToString("D12")+".bin"),new byte[0]);return;}
            DateTime deadline=DateTime.UtcNow.AddSeconds(30);
            while(index>=Window&&File.Exists(Path.Combine(dir,prefix+(index-Window).ToString("D12")+".bin"))){if(Closed(dir)||DateTime.UtcNow>deadline)throw new IOException("Reader unavailable");Thread.Sleep(10);}
            byte[] data=new byte[n];Buffer.BlockCopy(buffer,0,data,0,n);Atomic(Path.Combine(dir,prefix+(index++).ToString("D12")+".bin"),data);
        }
    }
    static void FromFiles(string dir,string prefix,TcpClient client) {
        long index=0;var stream=client.GetStream();
        while(!Closed(dir)){
            string p=Path.Combine(dir,prefix+(index++).ToString("D12")+".bin");DateTime deadline=DateTime.UtcNow.AddSeconds(90);
            while(!File.Exists(p)){if(Closed(dir)||DateTime.UtcNow>deadline)throw new IOException("Writer unavailable");Thread.Sleep(5);}
            if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0||new FileInfo(p).Length>Chunk)throw new IOException("Invalid chunk");
            byte[] data=File.ReadAllBytes(p);File.Delete(p);if(data.Length==0){client.Client.Shutdown(SocketShutdown.Send);return;}stream.Write(data,0,data.Length);stream.Flush();
        }
    }
    static void Relay(TcpClient client,string dir,string send,string receive) {
        try {
            client.NoDelay=true;client.ReceiveTimeout=90000;client.SendTimeout=30000;
            Task a=Task.Run(()=>ToFiles(client.GetStream(),dir,send));Task b=Task.Run(()=>FromFiles(dir,receive,client));
            int first=Task.WaitAny(a,b);if((first==0?a:b).IsFaulted)throw new IOException("Relay failed");
            if(!Task.WaitAll(new Task[]{a,b},95000))throw new IOException("Idle relay timed out");
        }catch{}finally{Close(dir);client.Close();Interlocked.Decrement(ref running);}
    }
    static void Broker() {
        Console.WriteLine("broker_ready=true; destination=loopback_proxy_only");
        while(true){
            foreach(string dir in Directory.GetDirectories(root)){
                string id=Path.GetFileName(dir);Guid g;
                if(!Guid.TryParseExact(id,"N",out g)||!File.Exists(Path.Combine(dir,"request"))||Closed(dir)||sessions.ContainsKey(id)||running>=MaxSessions)continue;
                string safe;try{safe=SafeDirectory(id);}catch{continue;}
                if(!sessions.TryAdd(id,0))continue;Interlocked.Increment(ref running);
                Task.Run(()=>{
                    try{
                        var client=new TcpClient(AddressFamily.InterNetwork);
                        var t=client.ConnectAsync(IPAddress.Loopback,proxyPort);if(!t.Wait(5000))throw new IOException("Proxy unavailable");
                        File.WriteAllText(Path.Combine(safe,"ready"),"ready");Relay(client,safe,"down-","up-");
                    }catch{Close(safe);Interlocked.Decrement(ref running);}
                });
            }
            if(sessions.Count>10000)throw new IOException("Restart broker with a fresh empty IPC directory");Thread.Sleep(15);
        }
    }
    static void Guest(int port) {
        var listener=new TcpListener(IPAddress.Loopback,port);listener.Start();Console.WriteLine("guest_proxy_ready=true");
        while(true){var client=listener.AcceptTcpClient();if(running>=MaxSessions){client.Close();continue;}Interlocked.Increment(ref running);
            Task.Run(()=>{string dir=null;try{
                dir=SafeDirectory(Guid.NewGuid().ToString("N"));Directory.CreateDirectory(dir);File.WriteAllText(Path.Combine(dir,"request"),"request");
                DateTime deadline=DateTime.UtcNow.AddSeconds(7);
                while(!File.Exists(Path.Combine(dir,"ready"))){if(Closed(dir)||DateTime.UtcNow>deadline)throw new IOException("Broker unavailable");Thread.Sleep(15);}
                Relay(client,dir,"up-","down-");
            }catch{if(dir!=null)Close(dir);client.Close();Interlocked.Decrement(ref running);}});
        }
    }
    static int Main(string[] args) {
        try {
            if(args.Length!=3||(args[0]!="broker"&&args[0]!="guest")){Console.Error.WriteLine("file-tunnel broker|guest IPC_DIRECTORY PORT");return 2;}
            root=Path.GetFullPath(args[1]);Directory.CreateDirectory(root);if((File.GetAttributes(root)&FileAttributes.ReparsePoint)!=0)throw new IOException("Reparse root refused");
            int port=int.Parse(args[2]);if(port<1||port>65535)return 2;
            if(args[0]=="broker"){proxyPort=port;Broker();}else Guest(port);return 0;
        }catch{Console.Error.WriteLine("Tunnel stopped. No alternate network route.");return 1;}
    }
}
