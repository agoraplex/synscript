import React from 'react';
import {
  useCallback,
  useEffect,
  useReducer,
  useState,
} from "react";
import { Platform } from "react-native";
import { NavigationContainer } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";

import { AuthContext, createAuthContext } from "./src/auth";

import EntitlementsScreen from "./src/screens/Entitlements";
import HomeScreen from "./src/screens/Home";
import ScanScreen from "./src/screens/Scan";
import SignInScreen from "./src/screens/SignIn";
import SquirtleScreen from "./src/screens/Squirtle";

import { brandingColors, styles } from "./src/styles";

import { BarCodeScanner } from "expo-barcode-scanner";
import * as Linking from "expo-linking";
import * as Location from "expo-location";
import * as SplashScreen from "expo-splash-screen";
import * as WebBrowser from "expo-web-browser";

import awsconfig from "./aws-exports";
import { Amplify, Hub } from "@aws-amplify/core";
import Auth from "@aws-amplify/auth";

// ----------------------------------------------------------------------
// HACK: pulled from veatech/mobile
const urlOpener = async (url, redirectUrl) => {
  console.log("urlOpener", {url, redirectUrl});
  const res = await WebBrowser.openAuthSessionAsync(url, redirectUrl);

  console.log("urlOpener", { url, redirectUrl, res: JSON.stringify(res), });

  if ((res?.type === "success") && (Platform.OS === "ios")) {
    // HACK: fixup the broken URL that we somehow get on iOS native in some states
    let fixedUrl = res?.url.replace(":///?", "://?");
    console.log("urlOpener (fix)", { url: res?.url, fixedUrl });

    // Why is this only on iOS? What happens on Android?
    await WebBrowser.dismissBrowser();
    return Linking.openURL(fixedUrl);
  }
};

const expoScheme = "squirtle";
let _redirectUrl = Linking.makeUrl();
console.log("_redirectUrl (before)", _redirectUrl);

// HACK: handle running in Expo on localhost and/or LAN
if (_redirectUrl.startsWith("exp://1")) {
  _redirectUrl = _redirectUrl + "/--/";
}
else if (_redirectUrl.startsWith(expoScheme)) {
  // nothing to do (?)
}
else {
  // Expo client (over WAN, I presume?)
  _redirectUrl = _redirectUrl + "/";
}
console.log("_redirectUrl (after)", _redirectUrl);

Amplify.configure({
  ...awsconfig,
  oauth: {
    ...awsconfig.oauth,
    redirectSignIn: _redirectUrl,
    redirectSignOut: _redirectUrl,
    urlOpener,
  },
  Analytics: {
    disabled: true,
  },
});
// ----------------------------------------------------------------------

const Stack = createNativeStackNavigator();

export default function App() {
  const [state, dispatch] = useReducer(
    (prevState, action) => {
      console.log("dispatch %s", action.type, {prevState, action});

      switch (action.type) {
      case "APP_READY":
        return {
          ...prevState,
          isLoading: false,
        };
      case "MISSING_TOKEN":
        action.authContext.user = null;
        return {
          ...prevState,
          user: null,
        };
      case "RESTORE_TOKEN":
        return {
          ...prevState,
          user: action.user,
          isLoading: false,
        };
      case "SIGN_IN":
        action.authContext.user = action.user;
        return {
          ...prevState,
          user: action.user,
          isSignout: false,
        };
      case "SIGN_OUT":
        action.authContext.user = null;
        return {
          ...prevState,
          user: null,
          isSignout: true,
        };
      default:
        return {...prevState};
      }
    },
    {
      isLoading: true,
      isSignout: false,
      user: null,
    });

  const authContext = createAuthContext(dispatch);

  // Register Amplify Auth listener
  useEffect(() => {
    const auth_listener = (data) => {
      console.log("Hub:auth", {data});
    };

    Hub.listen("auth", auth_listener);

    return (() => {
      Hub.remove("auth", auth_listener);
    });
  }, []);

  useEffect(() => {
    async function bootstrap () {
      try {
        await SplashScreen.preventAutoHideAsync;
        try {
          const user = await Auth.currentAuthenticatedUser();
          dispatch({ type: "SIGN_IN", user, authContext });
        }
        catch (e) {
          console.log("Auth.currentAuthenticatedUser", {e});
          dispatch({ type: "MISSING_TOKEN" });
        }

        // HACK: do this later in the flow
        const barcode_perms = await BarCodeScanner.requestPermissionsAsync();
        console.log("bootstrap", {barcode_perms});

        // HACK: do this later in the flow (also use listener for better response)
        const location_perms = await Location.requestForegroundPermissionsAsync();
        console.log("bootstrap", {location_perms});
      }
      catch (e) {
        // TODO: maybe handle errors?
        console.warn(e);
      }
      finally {
        dispatch({ type: "APP_READY" });
      }
    }

    bootstrap();
  }, []);

  const onNavigationReady = useCallback(async () => {
    if (state.isLoading) {
      await SplashScreen.hideAsync();
    }
  }, [state.isLoading]);

  if (state.isLoading) {
    return null;
  }

  return (
    <AuthContext.Provider value={authContext}>
      <NavigationContainer
        onReady={onNavigationReady}>
        <Stack.Navigator
          screenOptions={{
            headerStyle: {
              backgroundColor: brandingColors.secondary_3,
            },
            headerTintColor: brandingColors.secondary_1,
            headerTitle: {
              color: brandingColors.secondary_1,
            },
          }}>

          {(state.user === null) ? (
            <>
              <Stack.Screen name="SignIn" component={SignInScreen} options={{ title: "Sign in"}} />
            </>
          ) : (
            <>
              <Stack.Screen name="Home" component={HomeScreen} options={{ headerShown: false }} />
              <Stack.Screen name="Entitlements" component={EntitlementsScreen} />
              <Stack.Screen name="Scan" component={ScanScreen} options={{ title: "Verify Code" }} />
              <Stack.Screen name="Squirtle" component={SquirtleScreen} />
            </>
          )}

        </Stack.Navigator>
      </NavigationContainer>
    </AuthContext.Provider>
  );
}
