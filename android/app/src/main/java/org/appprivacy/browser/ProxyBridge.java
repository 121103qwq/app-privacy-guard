package org.appprivacy.browser;

import android.net.InetAddresses;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import javax.net.ssl.*;

// A byte relay to one configured proxy. It never opens a socket to a requested website.
public final class ProxyBridge implements AutoCloseable {
    private final GuardService service;
    private final ExecutorService pool=Executors.newCachedThreadPool();
    private final Set<Socket> sockets=Collections.synchronizedSet(new HashSet<>());
    private ServerSocket listener;
    private volatile boolean running;
    public volatile String address="";public volatile int upstreamPort;public volatile boolean tls;public volatile String serverName="";
    public ProxyBridge(GuardService service){this.service=service;}
    public void configure(String address,int port,boolean tls,String serverName){
        InetAddresses.parseNumericAddress(address);
        if(port<1||port>65535)throw new IllegalArgumentException("Invalid proxy port");
        if(tls&&(serverName.isEmpty()||!serverName.matches("[A-Za-z0-9.-]+")))throw new IllegalArgumentException("TLS proxy requires its certificate hostname");
        this.address=address;this.upstreamPort=port;this.tls=tls;this.serverName=serverName;
    }
    public int port(){return listener.getLocalPort();}
    public void start()throws IOException{
        listener=new ServerSocket(0,32,InetAddress.getByName("127.0.0.1"));running=true;
        pool.execute(()->{while(running)try{Socket client=listener.accept();sockets.add(client);pool.execute(()->forward(client));}catch(IOException ignored){}});
    }
    private void forward(Socket client){
        Socket upstream=null;
        String stage="ready";
        try{
            if(!running||GuardService.active!=service||address.isEmpty())throw new IOException("Guard not ready");
            Socket raw=new Socket();upstream=raw;sockets.add(raw);
            // Android creates the file descriptor lazily. Bind before protect(), without sending a packet.
            raw.bind(new InetSocketAddress(0));
            stage="protect_socket";
            // This is the sole outbound bypass. Numeric parsing prevents OS DNS lookup.
            if(!service.protect(raw))throw new IOException("Protected proxy socket failed");
            stage="connect_numeric_proxy";raw.connect(new InetSocketAddress(InetAddresses.parseNumericAddress(address),upstreamPort),5000);
            if(tls){
                SSLSocket secure=(SSLSocket)((SSLSocketFactory)SSLSocketFactory.getDefault()).createSocket(raw,serverName,upstreamPort,true);
                SSLParameters parameters=secure.getSSLParameters();parameters.setEndpointIdentificationAlgorithm("HTTPS");secure.setSSLParameters(parameters);secure.startHandshake();upstream=secure;sockets.add(secure);
            }
            final Socket outgoing=upstream;
            Future<?> upload=pool.submit(()->copy(client,outgoing));
            copy(outgoing,client);upload.cancel(true);
        }catch(Exception ignored){
            android.util.Log.i("PrivacyFixture","proxy_bridge_failed_stage="+stage+";type="+ignored.getClass().getSimpleName());
            try{client.getOutputStream().write("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".getBytes(StandardCharsets.US_ASCII));}catch(IOException ignored2){}
        }finally{closeSocket(client);if(upstream!=null)closeSocket(upstream);}
    }
    private void copy(Socket from,Socket to){try{byte[] buffer=new byte[16384];int n;while(running&&(n=from.getInputStream().read(buffer))!=-1){to.getOutputStream().write(buffer,0,n);to.getOutputStream().flush();}}catch(IOException ignored){}finally{try{to.shutdownOutput();}catch(IOException ignored){}}}
    private void closeSocket(Socket socket){try{socket.close();}catch(IOException ignored){}sockets.remove(socket);}
    @Override public void close(){running=false;try{if(listener!=null)listener.close();}catch(IOException ignored){}synchronized(sockets){for(Socket socket:sockets)try{socket.close();}catch(IOException ignored){}sockets.clear();}pool.shutdownNow();}
}
