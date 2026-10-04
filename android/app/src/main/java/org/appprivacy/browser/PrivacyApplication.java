package org.appprivacy.browser;
import android.app.Application;
import android.os.LocaleList;
import java.util.Locale;
import java.util.TimeZone;
public final class PrivacyApplication extends Application {
    public static void applyRegion(){Locale.setDefault(Locale.US);LocaleList.setDefault(new LocaleList(Locale.US));TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"));}
    @Override public void onCreate(){super.onCreate();applyRegion();}
}
