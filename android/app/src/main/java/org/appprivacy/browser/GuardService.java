package org.appprivacy.browser;

import android.app.*;
import android.content.Intent;
import android.net.VpnService;
import android.os.*;
import java.io.*;
import java.util.concurrent.atomic.AtomicLong;

public final class GuardService extends VpnService {
    public static volatile GuardService active;
    public static volatile ProxyBridge bridge;
    public static final AtomicLong droppedV4=new AtomicLong(),droppedV6=new AtomicLong(),droppedUdp=new AtomicLong();
    private ParcelFileDescriptor tunnel;
    private volatile boolean running;
    @Override public int onStartCommand(Intent intent,int flags,int id) {
        if(active!=null)return START_NOT_STICKY;
        try {
            NotificationManager nm=(NotificationManager)getSystemService(NOTIFICATION_SERVICE);
            nm.createNotificationChannel(new NotificationChannel("egress","Browser network guard",NotificationManager.IMPORTANCE_LOW));
            startForeground(1,new Notification.Builder(this,"egress").setSmallIcon(android.R.drawable.ic_lock_lock).setContentTitle("App Privacy Browser protected").setContentText("Only the configured explicit proxy can forward browser traffic.").build());
            Builder b=new Builder().setSession("App Privacy Browser only").setMtu(1500)
                .addAddress("192.0.2.2",32).addAddress("fd42:5052:4956::2",128)
                .addRoute("0.0.0.0",0).addRoute("::",0)
                .addDnsServer("192.0.2.53").addDnsServer("2001:db8::53");
            b.addAllowedApplication(getPackageName());
            tunnel=b.establish();if(tunnel==null)throw new IOException("VPN was not established");
            active=this;running=true;
            bridge=new ProxyBridge(this);bridge.start();
            new Thread(()->{
                try(FileInputStream input=new FileInputStream(tunnel.getFileDescriptor())){
                    byte[] packet=new byte[32768];int size;
                    while(running&&(size=input.read(packet))>=0){
                        if(size<1)continue;int version=(packet[0]>>4)&15;
                        if(version==4){droppedV4.incrementAndGet();if(size>9&&(packet[9]&255)==17)droppedUdp.incrementAndGet();}
                        if(version==6){droppedV6.incrementAndGet();if(size>6&&(packet[6]&255)==17)droppedUdp.incrementAndGet();}
                        // Every packet captured here is discarded. Only the bridge's explicitly protected socket goes out.
                    }
                }catch(IOException ignored){}
            },"deny-tunnel").start();
        }catch(Exception error){shutdown();stopSelf();}
        return START_NOT_STICKY;
    }
    private void shutdown(){
        running=false;active=null;
        if(bridge!=null){bridge.close();bridge=null;}
        if(tunnel!=null)try{tunnel.close();}catch(IOException ignored){}tunnel=null;
    }
    @Override public void onRevoke(){shutdown();stopSelf();super.onRevoke();android.os.Process.killProcess(android.os.Process.myPid());}
    @Override public void onDestroy(){shutdown();super.onDestroy();}
}
