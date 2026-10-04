package org.appprivacy.browser;

import android.app.*;
import android.content.*;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.net.*;
import android.os.*;
import android.text.InputType;
import android.view.*;
import android.webkit.*;
import android.widget.*;
import androidx.webkit.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

public final class MainActivity extends Activity {
    private EditText host,port,certificate,url;private CheckBox tls;private TextView status;private LinearLayout layout,rootLayout;private ScrollView controls;
    private WebView web;private boolean ready,egressVerified;private long configEpoch;private String state;private final Handler handler=new Handler(Looper.getMainLooper());
    private final String labOrigin="https://appassets.androidplatform.net";
    @Override protected void attachBaseContext(Context base){Configuration c=new Configuration(base.getResources().getConfiguration());c.setLocale(Locale.US);super.attachBaseContext(base.createConfigurationContext(c));}
    @Override public void onCreate(Bundle saved){
        super.onCreate(saved);getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        PrivacyApplication.applyRegion();
        layout=new LinearLayout(this);layout.setOrientation(LinearLayout.VERTICAL);layout.setPadding(16,12,16,12);
        rootLayout=new LinearLayout(this);rootLayout.setOrientation(LinearLayout.VERTICAL);controls=new ScrollView(this);controls.addView(layout);rootLayout.addView(controls,new LinearLayout.LayoutParams(-1,-1));
        status=new TextView(this);status.setText("Guard stopped. No browser is created before protection is ready.");layout.addView(status);
        host=field("Numeric proxy address","",false);port=field("Proxy port","17992",true);certificate=field("TLS certificate hostname","",false);
        tls=new CheckBox(this);tls.setText("TLS upstream proxy (required outside a trusted local network)");layout.addView(tls);
        SharedPreferences p=getSharedPreferences("proxy",MODE_PRIVATE);host.setText(p.getString("host",""));port.setText(p.getString("port","17992"));certificate.setText(p.getString("certificate",""));tls.setChecked(p.getBoolean("tls",false));
        button("Start guard",()->prepare());
        url=field("HTTPS URL","https://example.invalid",false);button("Open HTTPS URL",()->openNormal());
        button("Run synthetic app-browser-callback flow",()->openLab());
        button("Probe blocked IPv4 / IPv6 / DNS / UDP",()->probe());
        button("Stop guard",()->{ready=false;closeWeb();stopService(new Intent(this,GuardService.class));status.setText("Guard stopped; browser closed. No direct fallback.");});
        setContentView(rootLayout);
        handler.postDelayed(new Runnable(){public void run(){if(ready&&GuardService.active==null){ready=false;closeWeb();status.setText("VPN guard lost; browser closed.");}handler.postDelayed(this,250);}},250);
    }
    private EditText field(String hint,String value,boolean numeric){EditText e=new EditText(this);e.setHint(hint);e.setText(value);e.setSingleLine();e.setSelectAllOnFocus(true);if(numeric)e.setInputType(InputType.TYPE_CLASS_NUMBER);layout.addView(e);return e;}
    private void button(String label,Runnable run){Button b=new Button(this);b.setText(label);b.setAllCaps(false);b.setOnClickListener(v->run.run());layout.addView(b);}
    private void prepare(){try{InetAddresses.parseNumericAddress(host.getText().toString().trim());Integer.parseInt(port.getText().toString());Intent consent=android.net.VpnService.prepare(this);if(consent!=null)startActivityForResult(consent,1);else start();}catch(Exception e){status.setText("Enter a numeric proxy address and a valid port. No hostname DNS lookup is used.");}}
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==1&&result==RESULT_OK)start();else status.setText("VPN permission not granted. Browser remains closed.");}
    private void start(){
        ready=false;egressVerified=false;++configEpoch;closeWeb();
        startForegroundService(new Intent(this,GuardService.class));
        getSharedPreferences("proxy",MODE_PRIVATE).edit().putString("host",host.getText().toString().trim()).putString("port",port.getText().toString()).putString("certificate",certificate.getText().toString().trim()).putBoolean("tls",tls.isChecked()).apply();
        awaitGuard(0);
    }
    private void awaitGuard(int attempts){
        if(GuardService.active==null||GuardService.bridge==null){if(attempts<40){handler.postDelayed(()->awaitGuard(attempts+1),100);return;}status.setText("VPN failed; browser remains closed.");return;}
        try{
            GuardService.bridge.configure(host.getText().toString().trim(),Integer.parseInt(port.getText().toString()),tls.isChecked(),certificate.getText().toString().trim());
            if(!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)||!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT))throw new Exception("System WebView lacks required proxy/document-start support");
            ProxyConfig config=new ProxyConfig.Builder().addProxyRule("http://127.0.0.1:"+GuardService.bridge.port()).addBypassRule("<-loopback>").build();
            final long checkedEpoch=configEpoch;
            ProxyController.getInstance().setProxyOverride(config,getMainExecutor(),()->{
                if(checkedEpoch!=configEpoch)return;
                ready=true;egressVerified=false;status.setText("Guard ready. Checking US proxy egress; browsing remains closed.");
                ProxyBridge checked=GuardService.bridge;
                new Thread(()->{boolean us=ProxyCheck.isUs(checked.port());runOnUiThread(()->{if(checked!=GuardService.bridge||checkedEpoch!=configEpoch)return;egressVerified=us;status.setText(us?"Guard ready; US egress verified. No DIRECT rule.":"US proxy check failed. Only offline synthetic tests are enabled.");android.util.Log.i("PrivacyFixture","proxy_us_verified="+us);});},"proxy-country-check").start();
            });
        }catch(Exception e){ready=false;status.setText("Protection unavailable; browser remains closed: "+e.getMessage());}
    }
    private String asset(String name)throws IOException{try(InputStream in=getAssets().open(name);ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1)out.write(b,0,n);return new String(out.toByteArray(),StandardCharsets.UTF_8);}}
    private void create(boolean lab)throws IOException{
        if(!ready||GuardService.active==null)throw new IOException("Guard is not ready");
        closeWeb();web=new WebView(this);PrivacyApplication.applyRegion();
        WebSettings s=web.getSettings();s.setJavaScriptEnabled(true);s.setDomStorageEnabled(true);s.setGeolocationEnabled(false);s.setAllowFileAccess(false);s.setAllowContentAccess(false);s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);s.setMediaPlaybackRequiresUserGesture(true);
        WebViewCompat.addDocumentStartJavaScript(web,asset("region-start.js"),Collections.singleton("*"));
        if(WebViewFeature.isFeatureSupported(WebViewFeature.SERVICE_WORKER_BLOCK_NETWORK_LOADS))ServiceWorkerControllerCompat.getInstance().getServiceWorkerWebSettings().setBlockNetworkLoads(true);
        web.setWebChromeClient(new WebChromeClient(){@Override public void onPermissionRequest(PermissionRequest p){p.deny();}@Override public void onGeolocationPermissionsShowPrompt(String o,GeolocationPermissions.Callback callback){callback.invoke(o,false,false);}});
        web.setWebViewClient(new WebViewClient(){
            @Override public WebResourceResponse shouldInterceptRequest(WebView view,WebResourceRequest request){
                if(lab&&"appassets.androidplatform.net".equals(request.getUrl().getHost()))try{return new WebResourceResponse("text/html","UTF-8",getAssets().open("flow.html"));}catch(IOException e){return new WebResourceResponse("text/plain","UTF-8",new ByteArrayInputStream(new byte[0]));}
                return null;
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
                Uri u=request.getUrl();
                if(lab&&"appprivacy".equals(u.getScheme())&&"callback".equals(u.getHost())){
                    boolean bound=state!=null&&state.equals(u.getQueryParameter("state"))&&"mock-only".equals(u.getQueryParameter("code"));
                    status.setText(bound?"Synthetic callback verified. No real account or token was used.":"Callback rejected: wrong state/code.");
                    android.util.Log.i("PrivacyFixture",bound?"callback_bound=true":"callback_bound=false");return true;
                }
                // Never hand browsing or OAuth links to an unprotected external app.
                if(!"https".equals(u.getScheme()))return true;
                if(lab&&!"appassets.androidplatform.net".equals(u.getHost()))return true;
                return false;
            }
            @Override public void onReceivedError(WebView v,WebResourceRequest r,WebResourceError error){if(r.isForMainFrame())status.setText("Page failed; no direct retry is performed.");}
            @Override public void onReceivedSslError(WebView v,SslErrorHandler h,android.net.http.SslError e){h.cancel();status.setText("TLS error; connection stopped.");}
        });
        if(lab)web.addJavascriptInterface(new Object(){@JavascriptInterface public void record(String report){try{JSONObject j=new JSONObject(report);j.put("java_locale_us",Locale.getDefault().equals(Locale.US));j.put("java_timezone_us",TimeZone.getDefault().getID().equals("America/Los_Angeles"));if(report.length()<12000)android.util.Log.i("PrivacyFixture",j.toString());}catch(Exception ignored){}}},"Fixture");
        controls.setLayoutParams(new LinearLayout.LayoutParams(-1,(int)(240*getResources().getDisplayMetrics().density)));
        rootLayout.addView(web,new LinearLayout.LayoutParams(-1,0,1));
    }
    private void closeWeb(){if(web!=null){web.stopLoading();rootLayout.removeView(web);web.destroy();web=null;}controls.setLayoutParams(new LinearLayout.LayoutParams(-1,-1));}
    private void openNormal(){try{if(!egressVerified)throw new IOException("A working US proxy must be verified first.");Uri u=Uri.parse(url.getText().toString().trim());if(!"https".equals(u.getScheme()))throw new IOException("HTTPS is required");create(false);web.loadUrl(u.toString(),Collections.singletonMap("Accept-Language","en-US,en;q=0.9"));}catch(Exception e){status.setText(e.getMessage());}}
    private void openLab(){try{state=UUID.randomUUID().toString();create(true);web.loadUrl(labOrigin+"/flow?state="+state);}catch(Exception e){status.setText(e.getMessage());}}
    private void probe(){
        if(!ready){status.setText("Start the guard first.");return;}
        new Thread(()->{
            long v4=GuardService.droppedV4.get(),v6=GuardService.droppedV6.get(),udp=GuardService.droppedUdp.get();
            boolean tcp4=connectBlocked("192.0.2.99"),tcp6=connectBlocked("2001:db8::99");
            try(DatagramSocket socket=new DatagramSocket()){socket.setSoTimeout(500);socket.send(new DatagramPacket(new byte[]{1,2,3,4},4,InetAddresses.parseNumericAddress("198.51.100.99"),3478));try{socket.receive(new DatagramPacket(new byte[128],128));}catch(IOException ignored){}}catch(IOException ignored){}
            // A raw DNS packet to a documentation-range address must also enter the deny tunnel.
            try(DatagramSocket socket=new DatagramSocket()){socket.send(new DatagramPacket(new byte[32],32,InetAddresses.parseNumericAddress("192.0.2.53"),53));}catch(IOException ignored){}
            try{Thread.sleep(300);}catch(InterruptedException ignored){}
            JSONObject result=new JSONObject();try{result.put("direct_tcp4_denied",tcp4);result.put("direct_tcp6_denied",tcp6);result.put("tunnel_v4_drops",GuardService.droppedV4.get()-v4);result.put("tunnel_v6_drops",GuardService.droppedV6.get()-v6);result.put("tunnel_udp_drops",GuardService.droppedUdp.get()-udp);result.put("addresses_are_documentation_ranges",true);}catch(JSONException ignored){}
            android.util.Log.i("PrivacyFixture",result.toString());runOnUiThread(()->status.setText(result.toString()));
        },"safe-canary-probes").start();
    }
    private boolean connectBlocked(String address){try(Socket socket=new Socket()){socket.connect(new InetSocketAddress(InetAddresses.parseNumericAddress(address),443),800);return false;}catch(IOException e){return true;}}
    @Override public void onBackPressed(){if(web!=null&&web.canGoBack())web.goBack();else super.onBackPressed();}
    @Override protected void onResume(){super.onResume();PrivacyApplication.applyRegion();}
    @Override protected void onDestroy(){ready=false;closeWeb();stopService(new Intent(this,GuardService.class));super.onDestroy();}
}
