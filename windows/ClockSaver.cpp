// Cool Clock Windows screensaver host. Web assets are local and share one WebView2 environment.
#ifndef CLOCK_PARSER_TEST
#define _WIN32_WINNT 0x0A00
#define WINVER 0x0A00
#endif
#include <string>
#include <vector>
#include <cstdint>
#include <cwchar>
#include <cerrno>
#include <limits>

enum class Mode { Config, Screen, Embedded, Window, CheckRuntime, SelfTest, CloseExisting };
struct Arguments {
    Mode mode = Mode::Config;
    uintptr_t parent = 0;
    std::wstring report;
    std::wstring closeTarget;
    unsigned seconds = 0;
};
static bool Number(const std::wstring& s, uintptr_t& value) {
    if (s.empty() || s.find_first_not_of(L"0123456789") != std::wstring::npos) return false;
    errno = 0;
    wchar_t* end = nullptr;
    unsigned long long n = std::wcstoull(s.c_str(), &end, 10);
    if (errno || *end || n > std::numeric_limits<uintptr_t>::max()) return false;
    value = static_cast<uintptr_t>(n);
    return true;
}
static bool ProductionVersion(const std::wstring& version) {
    size_t start=0;
    bool nonzero=false;
    for(unsigned part=0;part<4;++part){
        size_t end=version.find(L'.',start);
        if((part<3 && end==std::wstring::npos)||(part==3 && end!=std::wstring::npos))return false;
        uintptr_t value=0;
        if(!Number(version.substr(start,end==std::wstring::npos?end:end-start),value))return false;
        nonzero |= value!=0;
        start=end+1;
    }
    return nonzero;
}
static bool AbsoluteWindowsPath(const std::wstring& path) {
    if(path.size()>=3&&((path[0]>=L'A'&&path[0]<=L'Z')||(path[0]>=L'a'&&path[0]<=L'z'))&&path[1]==L':'&&(path[2]==L'\\'||path[2]==L'/'))return true;
    if(path.size()>4&&path[0]==L'\\'&&path[1]==L'\\'){
        size_t share=path.find(L'\\',2);
        return share!=std::wstring::npos&&share>2&&share+1<path.size();
    }
    return false;
}
static bool Parse(const std::vector<std::wstring>& args, Arguments& out) {
    bool modeSeen = false;
    for (size_t i = 0; i < args.size(); ++i) {
        std::wstring a = args[i];
        if (a == L"--smoke-report" && i + 1 < args.size()) { out.report = args[++i]; continue; }
        if (a == L"--seconds" && i + 1 < args.size()) {
            uintptr_t n = 0;
            if (!Number(args[++i], n) || n < 1 || n > 3600) return false;
            out.seconds = static_cast<unsigned>(n); continue;
        }
        if (modeSeen) return false;
        modeSeen = true;
        if (a == L"--close-existing") {
            out.mode=Mode::CloseExisting;
            if(i+1==args.size()||!AbsoluteWindowsPath(args[++i]))return false;
            out.closeTarget=args[i];
        }
        else if (a == L"--preview") out.mode = Mode::Window;
        else if (a == L"--check-runtime") out.mode = Mode::CheckRuntime;
        else if (a == L"--self-test") out.mode = Mode::SelfTest;
        else {
            for (auto& c : a) if (c >= L'A' && c <= L'Z') c += L'a' - L'A';
            if (a == L"/s" || a == L"-s") out.mode = Mode::Screen;
            else if (a == L"/c" || a == L"-c" || a.rfind(L"/c:", 0) == 0) {
                out.mode = Mode::Config;
                if (a.size() > 2 && !Number(a.substr(3), out.parent)) return false;
                if (a.size() == 2 && i + 1 < args.size() && Number(args[i + 1], out.parent)) ++i;
            } else if (a == L"/p" || a == L"-p" || a.rfind(L"/p:", 0) == 0) {
                out.mode = Mode::Embedded;
                if (a.size() > 2) { if (!Number(a.substr(3), out.parent)) return false; }
                else if (i + 1 == args.size() || !Number(args[++i], out.parent)) return false;
                if (!out.parent) return false;
            } else return false;
        }
    }
    return (out.report.empty() && out.seconds == 0) || out.mode == Mode::Window || out.mode == Mode::Screen || out.mode == Mode::Embedded;
}
static bool LocalResource(const std::wstring& uri) { return uri.rfind(L"https://cool-clock.local/", 0) == 0; }
static bool LocalPage(const std::wstring& uri) {
    constexpr auto page = L"https://cool-clock.local/clock.html";
    return uri == page || uri.rfind(std::wstring(page) + L"?", 0) == 0;
}
static bool AcceptedMessage(const std::wstring& message) {
    return message==L"ready"||message==L"exit"||message==L"sound:on"||message==L"sound:off"||message==L"error";
}
static int SelfTest() {
    struct Case { std::vector<std::wstring> args; bool ok; Mode mode; uintptr_t parent; };
    const Case cases[] = {
        {{L"--close-existing",L"C:\\Users\\Test\\Cool Clock.scr"},true,Mode::CloseExisting,0},
        {{L"--close-existing",L"\\\\server\\share\\Clock.scr"},true,Mode::CloseExisting,0},
        {{L"--close-existing"},false,Mode::Config,0},
        {{L"--close-existing",L"Clock.scr"},false,Mode::Config,0},
        {{L"--close-existing",L"C:Clock.scr"},false,Mode::Config,0},
        {{L"--close-existing",L"\\Clock.scr"},false,Mode::Config,0},
        {{L"--close-existing",L"C:\\Clock.scr",L"/s"},false,Mode::Config,0},
        {{},true,Mode::Config,0}, {{L"/S"},true,Mode::Screen,0},
        {{L"/c:123"},true,Mode::Config,123}, {{L"/c",L"123"},true,Mode::Config,123},
        {{L"/p",L"4294967295"},true,Mode::Embedded,4294967295ULL},
        {{L"/p:123"},true,Mode::Embedded,123}, {{L"--preview"},true,Mode::Window,0},
        {{L"/p"},false,Mode::Config,0}, {{L"/p:0"},false,Mode::Config,0},
        {{L"/p",L"-2"},false,Mode::Config,0}, {{L"/c:"},false,Mode::Config,0},
        {{L"/p",L"18446744073709551616"},false,Mode::Config,0},
        {{L"/s",L"/c"},false,Mode::Config,0}, {{L"--wat"},false,Mode::Config,0},
        {{L"--preview",L"--seconds",L"3",L"--smoke-report",L"report.json"},true,Mode::Window,0},
        {{L"/p",L"123",L"--seconds",L"15",L"--smoke-report",L"embedded.json"},true,Mode::Embedded,123},
        {{L"--seconds",L"0"},false,Mode::Config,0}, {{L"--seconds",L"3"},false,Mode::Config,0}
    };
    for (const auto& c : cases) { Arguments a; bool ok = Parse(c.args,a); if (ok != c.ok || (ok && (a.mode != c.mode || a.parent != c.parent))) return 1; }
    Arguments closeArgs;
    if(!Parse({L"--close-existing",L"C:\\Clock.scr"},closeArgs)||closeArgs.closeTarget!=L"C:\\Clock.scr")return 8;
    if (!LocalResource(L"https://cool-clock.local/assets/a.mp4") || LocalResource(L"https://cool-clock.local.evil/a") || LocalResource(L"http://cool-clock.local/a")) return 2;
    if (!LocalPage(L"https://cool-clock.local/clock.html?mode=screen") || LocalPage(L"https://cool-clock.local/other") || LocalPage(L"https://cool-clock.local/clock.html.evil")) return 3;
    if(!ProductionVersion(L"156.0.4314.35")||!ProductionVersion(L"0.0.0.1"))return 4;
    for(const auto* invalid:{L"",L"0.0.0.0",L"1.2.3",L"1.2.3.4.5",L"1.2.-3.4",L"1.2.3.4 beta",L"1.2.3."})if(ProductionVersion(invalid))return 5;
    for(const auto* message:{L"ready",L"exit",L"sound:on",L"sound:off",L"error"})if(!AcceptedMessage(message))return 6;
    for(const auto* message:{L"",L"Error",L"error:detail",L"sound:toggle",L"ready ",L"{\"error\":true}"})if(AcceptedMessage(message))return 7;
    return 0;
}
#ifdef CLOCK_PARSER_TEST
int main() { return SelfTest(); }
#else
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <wtsapi32.h>
#include <WebView2.h>
#include <functional>
#include <memory>
#include <cstdio>
#include <algorithm>
#include <map>

// The installer runs its freshly extracted host to close only this user's exact installation.
static std::vector<BYTE> ProcessUser(HANDLE process) {
    HANDLE token=nullptr;
    if(!OpenProcessToken(process,TOKEN_QUERY,&token))return {};
    DWORD size=0;GetTokenInformation(token,TokenUser,nullptr,0,&size);
    std::vector<BYTE> data(size);
    bool ok=size&&GetTokenInformation(token,TokenUser,data.data(),size,&size);
    CloseHandle(token);
    if(!ok)data.clear();
    return data;
}
struct CloseRequest {
    std::wstring target;
    std::vector<BYTE> user;
    std::map<DWORD,HANDLE> processes;
    bool failed=false;
};
static BOOL CALLBACK CloseCandidate(HWND window,LPARAM parameter) {
    auto& request=*reinterpret_cast<CloseRequest*>(parameter);
    wchar_t className[32]{};
    if(!GetClassNameW(window,className,32)||wcscmp(className,L"CoolClock")!=0)return TRUE;
    DWORD pid=0;GetWindowThreadProcessId(window,&pid);
    if(!pid||pid==GetCurrentProcessId()||request.processes.count(pid))return TRUE;
    HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,pid);
    if(!process)return TRUE;
    wchar_t image[32768];DWORD length=32768;
    if(!QueryFullProcessImageNameW(process,0,image,&length)||_wcsicmp(image,request.target.c_str())!=0){CloseHandle(process);return TRUE;}
    auto owner=ProcessUser(process);
    if(owner.empty()){request.failed=true;CloseHandle(process);return TRUE;}
    if(!EqualSid(reinterpret_cast<TOKEN_USER*>(owner.data())->User.Sid,reinterpret_cast<TOKEN_USER*>(request.user.data())->User.Sid)){CloseHandle(process);return TRUE;}
    request.processes.emplace(pid,process);
    if(!PostMessageW(window,WM_CLOSE,0,0))request.failed=true;
    return TRUE;
}
static BOOL CALLBACK CloseTopLevel(HWND window,LPARAM parameter) {
    CloseCandidate(window,parameter);
    EnumChildWindows(window,CloseCandidate,parameter);
    return TRUE;
}
static int CloseExisting(const std::wstring& target) {
    wchar_t absolute[32768];DWORD length=GetFullPathNameW(target.c_str(),32768,absolute,nullptr);
    if(!length||length>=32768)return 2;
    CloseRequest request;request.target.assign(absolute,length);request.user=ProcessUser(GetCurrentProcess());
    if(request.user.empty())return 2;
    ULONGLONG deadline=GetTickCount64()+5000;
    EnumWindows(CloseTopLevel,reinterpret_cast<LPARAM>(&request));
    for(const auto& entry:request.processes){
        ULONGLONG now=GetTickCount64();
        DWORD remaining=now>=deadline?0:static_cast<DWORD>(deadline-now);
        if(WaitForSingleObject(entry.second,remaining)!=WAIT_OBJECT_0)request.failed=true;
        CloseHandle(entry.second);
    }
    return request.failed?1:0;
}

// Every callback has ordinary COM ownership. All callbacks execute on the STA UI thread.
template<class I, class... Args> class Callback final : public I {
    ULONG refs = 1; IID iid; std::function<HRESULT(Args...)> fn;
public:
    Callback(REFIID id, std::function<HRESULT(Args...)> f) : iid(id), fn(std::move(f)) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void** p) override {
        if (!p) return E_POINTER; *p = nullptr;
        if (IsEqualIID(id, IID_IUnknown) || IsEqualIID(id, iid)) { *p = static_cast<I*>(this); AddRef(); return S_OK; }
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
    ULONG STDMETHODCALLTYPE Release() override { ULONG n = --refs; if (!n) delete this; return n; }
    HRESULT STDMETHODCALLTYPE Invoke(Args... args) override { return fn(args...); }
};
template<class I, class... A, class F> static I* Handler(REFIID iid, F f) { return new Callback<I,A...>(iid, std::move(f)); }
template<class T> static void Release(T*& p) { if (p) { p->Release(); p = nullptr; } }
class Options final : public ICoreWebView2EnvironmentOptions {
    ULONG refs = 1;
    std::wstring arguments = L"--autoplay-policy=no-user-gesture-required", language;
    std::wstring version = L"92.0.902.49"; // API floor for ICoreWebView2_4, the newest interface used here.
    BOOL signOn = FALSE;
    static HRESULT Copy(const std::wstring& s, LPWSTR* p) {
        if (!p) return E_POINTER;
        *p = nullptr;
        if (s.empty()) return S_OK;
        *p = static_cast<LPWSTR>(CoTaskMemAlloc((s.size()+1)*sizeof(wchar_t)));
        if (!*p) return E_OUTOFMEMORY;
        memcpy(*p,s.c_str(),(s.size()+1)*sizeof(wchar_t)); return S_OK;
    }
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** p) override { if (!p) return E_POINTER; *p=nullptr; if (IsEqualIID(id,IID_IUnknown)||IsEqualIID(id,IID_ICoreWebView2EnvironmentOptions)) {*p=this;AddRef();return S_OK;}return E_NOINTERFACE; }
    ULONG STDMETHODCALLTYPE AddRef() override {return ++refs;}
    ULONG STDMETHODCALLTYPE Release() override {ULONG n=--refs;if(!n)delete this;return n;}
    HRESULT STDMETHODCALLTYPE get_AdditionalBrowserArguments(LPWSTR* p) override {return Copy(arguments,p);}
    HRESULT STDMETHODCALLTYPE put_AdditionalBrowserArguments(LPCWSTR p) override {arguments=p?p:L"";return S_OK;}
    HRESULT STDMETHODCALLTYPE get_Language(LPWSTR* p) override {return Copy(language,p);}
    HRESULT STDMETHODCALLTYPE put_Language(LPCWSTR p) override {language=p?p:L"";return S_OK;}
    HRESULT STDMETHODCALLTYPE get_TargetCompatibleBrowserVersion(LPWSTR* p) override {return Copy(version,p);}
    HRESULT STDMETHODCALLTYPE put_TargetCompatibleBrowserVersion(LPCWSTR p) override {version=p?p:L"";return S_OK;}
    HRESULT STDMETHODCALLTYPE get_AllowSingleSignOnUsingOSPrimaryAccount(BOOL* p) override {if(!p)return E_POINTER;*p=signOn;return S_OK;}
    HRESULT STDMETHODCALLTYPE put_AllowSingleSignOnUsingOSPrimaryAccount(BOOL p) override {signOn=p;return S_OK;}
};
static int OptionsSelfTest() {
    auto options=new Options();
    LPWSTR version=nullptr,language=nullptr;
    bool ok=SUCCEEDED(options->get_TargetCompatibleBrowserVersion(&version))&&version&&ProductionVersion(version);
    ok=ok&&SUCCEEDED(options->get_Language(&language))&&!language;
    CoTaskMemFree(version);CoTaskMemFree(language);options->Release();
    return ok?0:9;
}
struct View { HWND hwnd=nullptr; ICoreWebView2Controller* controller=nullptr; ICoreWebView2* web=nullptr; bool primary=false,ready=false,paused=false; std::wstring error; };
static Arguments options;
static std::vector<std::unique_ptr<View>> views;
static ICoreWebView2Environment* environment=nullptr;
static HINSTANCE instance;
static HWND configWindow=nullptr, soundCheck=nullptr;
static HFONT configFont=nullptr;
static bool sound=false,stopping=false;
static int resultCode=0;
static ULONGLONG started=0;
static DWORD inputBaseline=0;
static std::wstring exeDirectory;
static std::vector<std::wstring> errors;
// Microsoft distribution guidance identifies Evergreen by this product's pv value.
// A browser-version query alone also succeeds with Edge preview channels installed.
static bool EvergreenInstalled(HKEY hive,REGSAM registryView) {
    HKEY key=nullptr;
    constexpr auto path=L"SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}";
    if(RegOpenKeyExW(hive,path,0,KEY_QUERY_VALUE|registryView,&key)!=ERROR_SUCCESS)return false;
    wchar_t version[128]{};
    DWORD size=sizeof(version),type=0;
    auto code=RegQueryValueExW(key,L"pv",nullptr,&type,reinterpret_cast<BYTE*>(version),&size);
    RegCloseKey(key);
    if(code!=ERROR_SUCCESS||type!=REG_SZ||size<sizeof(wchar_t)||size>sizeof(version)||size%sizeof(wchar_t))return false;
    if(version[size/sizeof(wchar_t)-1]!=L'\0')return false;
    return ProductionVersion(version);
}
static bool ReadSound() {
    HKEY key=nullptr;
    if(RegOpenKeyExW(HKEY_CURRENT_USER,L"Software\\CoolClock",0,KEY_QUERY_VALUE|KEY_WOW64_64KEY,&key)!=ERROR_SUCCESS)return false;
    DWORD value=0,size=sizeof(value),type=0;
    auto code=RegQueryValueExW(key,L"SoundEnabled",nullptr,&type,reinterpret_cast<BYTE*>(&value),&size);
    RegCloseKey(key);
    return code==ERROR_SUCCESS && type==REG_DWORD && size==sizeof(value) && value==1;
}
static bool WriteSound(bool enabled) {
    HKEY key=nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER,L"Software\\CoolClock",0,nullptr,0,KEY_SET_VALUE|KEY_WOW64_64KEY,nullptr,&key,nullptr)!=ERROR_SUCCESS) return false;
    DWORD value=enabled?1:0;
    auto code=RegSetValueExW(key,L"SoundEnabled",0,REG_DWORD,reinterpret_cast<const BYTE*>(&value),sizeof(value));RegCloseKey(key);return code==ERROR_SUCCESS;
}
static void Stop() {
    if(stopping)return;stopping=true;
    for(auto& v:views) {
        if(v->web)v->web->PostWebMessageAsString(L"pause");
        if(v->controller)v->controller->Close();
        Release(v->web);Release(v->controller);
        if(IsWindow(v->hwnd)){WTSUnRegisterSessionNotification(v->hwnd);DestroyWindow(v->hwnd);}
    }
    if(IsWindow(configWindow))DestroyWindow(configWindow);
    if(configFont){DeleteObject(configFont);configFont=nullptr;}
    PostQuitMessage(resultCode);
}
static void Error(View* v,const std::wstring& message,HRESULT code=E_FAIL) {
    wchar_t hex[32]; swprintf(hex,32,L" (0x%08lX)",static_cast<unsigned long>(code));
    std::wstring text=message+hex; errors.push_back(text);resultCode=1;
    if(v) {v->error=text; if(v->controller)v->controller->put_IsVisible(FALSE);InvalidateRect(v->hwnd,nullptr,TRUE);}
    else {if(options.report.empty())MessageBoxW(nullptr,text.c_str(),L"Cool Clock",MB_OK|MB_ICONERROR);Stop();}
}
static void Pause(View* v,bool pause) {
    if(v->paused==pause)return;v->paused=pause;
    if(v->web)v->web->PostWebMessageAsString(pause?L"pause":L"resume");
    if(v->controller)v->controller->put_IsVisible(!pause);
}
static void Resize(View* v) {if(v->controller){RECT r;GetClientRect(v->hwnd,&r);v->controller->put_Bounds(r);}}
static void Attach(View* v) {
    auto handler=Handler<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler,HRESULT,ICoreWebView2Controller*>(IID_ICoreWebView2CreateCoreWebView2ControllerCompletedHandler,[v](HRESULT hr,ICoreWebView2Controller* controller)->HRESULT {
        if(stopping||!IsWindow(v->hwnd)){if(controller)controller->Close();return S_OK;}
        if(FAILED(hr)||!controller){Error(v,L"Не удалось запустить окно WebView2",hr);return S_OK;}
        v->controller=controller;controller->AddRef();
        hr=controller->get_CoreWebView2(&v->web);if(FAILED(hr)){Error(v,L"Не удалось получить WebView2",hr);return S_OK;}
        ICoreWebView2_3* local=nullptr;
        hr=v->web->QueryInterface(IID_ICoreWebView2_3,reinterpret_cast<void**>(&local));
        if(FAILED(hr)){Error(v,L"Обновите Microsoft Edge WebView2 Runtime",hr);return S_OK;}
        hr=local->SetVirtualHostNameToFolderMapping(L"cool-clock.local",(exeDirectory+L"\\web").c_str(),COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS);Release(local);
        if(FAILED(hr)){Error(v,L"Не удалось открыть локальные файлы заставки",hr);return S_OK;}
        bool secured=true;
        ICoreWebView2Settings* settings=nullptr;
        if(SUCCEEDED(v->web->get_Settings(&settings))){secured &= SUCCEEDED(settings->put_AreDevToolsEnabled(FALSE));secured &= SUCCEEDED(settings->put_AreDefaultContextMenusEnabled(FALSE));settings->put_IsStatusBarEnabled(FALSE);settings->put_IsZoomControlEnabled(FALSE);secured &= SUCCEEDED(settings->put_AreHostObjectsAllowed(FALSE));
            ICoreWebView2Settings3* shortcuts=nullptr;
            if(SUCCEEDED(settings->QueryInterface(IID_ICoreWebView2Settings3,reinterpret_cast<void**>(&shortcuts)))){shortcuts->put_AreBrowserAcceleratorKeysEnabled(FALSE);Release(shortcuts);}
            Release(settings);
        } else secured=false;
        EventRegistrationToken token{};
        auto navigation=Handler<ICoreWebView2NavigationStartingEventHandler,ICoreWebView2*,ICoreWebView2NavigationStartingEventArgs*>(IID_ICoreWebView2NavigationStartingEventHandler,[](ICoreWebView2*,ICoreWebView2NavigationStartingEventArgs* a)->HRESULT {LPWSTR uri=nullptr;a->get_Uri(&uri);a->put_Cancel(!uri||!LocalPage(uri));CoTaskMemFree(uri);return S_OK;});
        secured &= SUCCEEDED(v->web->add_NavigationStarting(navigation,&token));navigation->Release();
        auto newWindow=Handler<ICoreWebView2NewWindowRequestedEventHandler,ICoreWebView2*,ICoreWebView2NewWindowRequestedEventArgs*>(IID_ICoreWebView2NewWindowRequestedEventHandler,[](ICoreWebView2*,ICoreWebView2NewWindowRequestedEventArgs* a)->HRESULT {return a->put_Handled(TRUE);});
        secured &= SUCCEEDED(v->web->add_NewWindowRequested(newWindow,&token));newWindow->Release();
        auto permission=Handler<ICoreWebView2PermissionRequestedEventHandler,ICoreWebView2*,ICoreWebView2PermissionRequestedEventArgs*>(IID_ICoreWebView2PermissionRequestedEventHandler,[](ICoreWebView2*,ICoreWebView2PermissionRequestedEventArgs* a)->HRESULT {return a->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);});
        secured &= SUCCEEDED(v->web->add_PermissionRequested(permission,&token));permission->Release();
        secured &= SUCCEEDED(v->web->AddWebResourceRequestedFilter(L"*",COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL));
        auto resource=Handler<ICoreWebView2WebResourceRequestedEventHandler,ICoreWebView2*,ICoreWebView2WebResourceRequestedEventArgs*>(IID_ICoreWebView2WebResourceRequestedEventHandler,[](ICoreWebView2*,ICoreWebView2WebResourceRequestedEventArgs* a)->HRESULT {
            ICoreWebView2WebResourceRequest* request=nullptr;LPWSTR uri=nullptr;
            if(SUCCEEDED(a->get_Request(&request))){request->get_Uri(&uri);Release(request);}
            if(!uri||!LocalResource(uri)){ICoreWebView2WebResourceResponse* response=nullptr;if(SUCCEEDED(environment->CreateWebResourceResponse(nullptr,403,L"Blocked",L"",&response))){a->put_Response(response);Release(response);}}
            CoTaskMemFree(uri);return S_OK;
        });secured &= SUCCEEDED(v->web->add_WebResourceRequested(resource,&token));resource->Release();
        ICoreWebView2_4* downloads=nullptr;
        if(SUCCEEDED(v->web->QueryInterface(IID_ICoreWebView2_4,reinterpret_cast<void**>(&downloads)))) {
            auto download=Handler<ICoreWebView2DownloadStartingEventHandler,ICoreWebView2*,ICoreWebView2DownloadStartingEventArgs*>(IID_ICoreWebView2DownloadStartingEventHandler,[](ICoreWebView2*,ICoreWebView2DownloadStartingEventArgs* a)->HRESULT {return a->put_Cancel(TRUE);});
            secured &= SUCCEEDED(downloads->add_DownloadStarting(download,&token));download->Release();Release(downloads);
        } else {Error(v,L"Обновите Microsoft Edge WebView2 Runtime");return S_OK;}
        auto message=Handler<ICoreWebView2WebMessageReceivedEventHandler,ICoreWebView2*,ICoreWebView2WebMessageReceivedEventArgs*>(IID_ICoreWebView2WebMessageReceivedEventHandler,[v](ICoreWebView2*,ICoreWebView2WebMessageReceivedEventArgs* a)->HRESULT {
            LPWSTR source=nullptr,text=nullptr;a->get_Source(&source);
            if(source&&LocalPage(source)&&SUCCEEDED(a->TryGetWebMessageAsString(&text))&&text&&wcslen(text)<=16&&AcceptedMessage(text)) {
                if(wcscmp(text,L"error")==0){
                    if(v->error.empty()){
                        v->ready=false;
                        v->web->PostWebMessageAsString(L"pause");
                        Error(v,L"Ошибка воспроизведения видео или WebGL. Перезапустите заставку.");
                    }
                }
                else if(wcscmp(text,L"ready")==0&&v->error.empty()){v->ready=true;if(v->paused)v->web->PostWebMessageAsString(L"pause");}
                else if(wcscmp(text,L"exit")==0&&options.mode==Mode::Screen&&GetTickCount64()-started>=1500)Stop();
                else if(options.mode==Mode::Window&&(wcscmp(text,L"sound:on")==0||wcscmp(text,L"sound:off")==0)){
                    bool enabled=wcscmp(text,L"sound:on")==0;
                    if(WriteSound(enabled))sound=enabled;
                    else v->web->PostWebMessageAsString(sound?L"sound:on":L"sound:off");
                }
            }CoTaskMemFree(source);CoTaskMemFree(text);return S_OK;
        });v->web->add_WebMessageReceived(message,&token);message->Release();
        auto completed=Handler<ICoreWebView2NavigationCompletedEventHandler,ICoreWebView2*,ICoreWebView2NavigationCompletedEventArgs*>(IID_ICoreWebView2NavigationCompletedEventHandler,[v](ICoreWebView2*,ICoreWebView2NavigationCompletedEventArgs* a)->HRESULT {BOOL success=FALSE;a->get_IsSuccess(&success);if(!success&&!stopping)Error(v,L"Не удалось загрузить файлы заставки");return S_OK;});
        v->web->add_NavigationCompleted(completed,&token);completed->Release();
        auto failed=Handler<ICoreWebView2ProcessFailedEventHandler,ICoreWebView2*,ICoreWebView2ProcessFailedEventArgs*>(IID_ICoreWebView2ProcessFailedEventHandler,[v](ICoreWebView2*,ICoreWebView2ProcessFailedEventArgs*)->HRESULT {if(!stopping)Error(v,L"Процесс WebView2 остановлен. Перезапустите заставку.");return S_OK;});
        v->web->add_ProcessFailed(failed,&token);failed->Release();
        if(!secured){Error(v,L"Не удалось включить ограничения WebView2");return S_OK;}
        Resize(v);controller->put_IsVisible(!v->paused);
        std::wstring mode=options.mode==Mode::Screen?L"screen":options.mode==Mode::Embedded?L"preview":L"window";
        std::wstring url=L"https://cool-clock.local/clock.html?mode="+mode+L"&sound="+((sound&&v->primary&&options.mode!=Mode::Embedded)?L"1":L"0");
        hr=v->web->Navigate(url.c_str());if(FAILED(hr))Error(v,L"Не удалось открыть заставку",hr);
        return S_OK;
    });
    HRESULT hr=environment->CreateCoreWebView2Controller(v->hwnd,handler);handler->Release();if(FAILED(hr))Error(v,L"Не удалось создать окно WebView2",hr);
}
// Control coordinates are 96-DPI logical pixels; retain native system message typography.
static void LayoutConfig(UINT dpi) {
    struct Control { int id,x,y,width,height; };
    const Control controls[]={{100,24,25,400,28},{101,24,62,400,24},{IDOK,210,105,100,30},{IDCANCEL,320,105,100,30}};
    NONCLIENTMETRICSW metrics{};metrics.cbSize=sizeof(metrics);
    HFONT nextFont=nullptr;
    if(SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS,sizeof(metrics),&metrics,0,dpi))nextFont=CreateFontIndirectW(&metrics.lfMessageFont);
    if(!nextFont)nextFont=CreateFontW(-MulDiv(12,dpi,96),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,DEFAULT_QUALITY,DEFAULT_PITCH,L"Segoe UI");
    for(const auto& c:controls){
        HWND child=GetDlgItem(configWindow,c.id);
        SetWindowPos(child,nullptr,MulDiv(c.x,dpi,96),MulDiv(c.y,dpi,96),MulDiv(c.width,dpi,96),MulDiv(c.height,dpi,96),SWP_NOZORDER|SWP_NOACTIVATE);
        SendMessageW(child,WM_SETFONT,reinterpret_cast<WPARAM>(nextFont?nextFont:GetStockObject(DEFAULT_GUI_FONT)),TRUE);
    }
    if(configFont)DeleteObject(configFont);
    configFont=nextFont;
}
static LRESULT CALLBACK Procedure(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) {
    View* v=reinterpret_cast<View*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));
    if(msg==WM_NCCREATE){v=static_cast<View*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams);SetWindowLongPtrW(hwnd,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(v));if(v)v->hwnd=hwnd;}
    if(msg==WM_CLOSE){Stop();return 0;}
    if(msg==WM_ENDSESSION&&wp){Stop();return 0;}
    if(msg==WM_QUERYENDSESSION)return TRUE;
    if(msg==WM_WTSSESSION_CHANGE&&(wp==WTS_SESSION_LOCK||wp==WTS_SESSION_LOGOFF||wp==WTS_CONSOLE_DISCONNECT||wp==WTS_REMOTE_DISCONNECT)){Stop();return 0;}
    if(msg==WM_DPICHANGED&&!v&&hwnd==configWindow){
        auto r=reinterpret_cast<RECT*>(lp);
        SetWindowPos(hwnd,nullptr,r->left,r->top,r->right-r->left,r->bottom-r->top,SWP_NOZORDER|SWP_NOACTIVATE);
        LayoutConfig(HIWORD(wp));return 0;
    }
    if(msg==WM_COMMAND&&!v){
        if(LOWORD(wp)==IDOK){bool enabled=SendMessageW(soundCheck,BM_GETCHECK,0,0)==BST_CHECKED;if(!WriteSound(enabled)){MessageBoxW(hwnd,L"Не удалось сохранить настройку звука.",L"Cool Clock",MB_OK|MB_ICONERROR);return 0;}Stop();return 0;}
        if(LOWORD(wp)==IDCANCEL){Stop();return 0;}
    }
    if(v){
        if(msg==WM_SIZE){Resize(v);Pause(v,wp==SIZE_MINIMIZED);return 0;}
        if(msg==WM_DPICHANGED&&options.mode==Mode::Window){auto r=reinterpret_cast<RECT*>(lp);SetWindowPos(hwnd,nullptr,r->left,r->top,r->right-r->left,r->bottom-r->top,SWP_NOZORDER|SWP_NOACTIVATE);return 0;}
        if(msg==WM_SETCURSOR&&options.mode==Mode::Screen){SetCursor(nullptr);return TRUE;}
        if(msg==WM_ERASEBKGND){RECT r;GetClientRect(hwnd,&r);FillRect(reinterpret_cast<HDC>(wp),&r,static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));return 1;}
        if(msg==WM_PAINT){PAINTSTRUCT ps;HDC dc=BeginPaint(hwnd,&ps);if(!v->error.empty()){RECT r;GetClientRect(hwnd,&r);InflateRect(&r,-24,-24);SetTextColor(dc,RGB(255,255,255));SetBkMode(dc,TRANSPARENT);DrawTextW(dc,v->error.c_str(),-1,&r,DT_WORDBREAK|DT_CENTER);}EndPaint(hwnd,&ps);return 0;}
        if(msg==WM_TIMER&&v->primary){
            if(options.mode==Mode::Embedded){HWND parent=reinterpret_cast<HWND>(options.parent);if(!IsWindow(parent)){Stop();return 0;}RECT r;GetClientRect(parent,&r);SetWindowPos(hwnd,nullptr,0,0,r.right,r.bottom,SWP_NOZORDER|SWP_NOACTIVATE);Pause(v,!IsWindowVisible(parent)||IsIconic(GetAncestor(parent,GA_ROOT)));}
            else if(options.mode==Mode::Window)Pause(v,IsIconic(hwnd)||!IsWindowVisible(hwnd));
            ULONGLONG elapsed=GetTickCount64()-started;
            if(options.mode==Mode::Screen){LASTINPUTINFO input{sizeof(input),0};if(GetLastInputInfo(&input)){if(elapsed<1500)inputBaseline=input.dwTime;else if(input.dwTime!=inputBaseline){Stop();return 0;}}}
            if(elapsed>30000)for(auto& view:views)if(!view->ready&&view->error.empty())Error(view.get(),L"Облака не загрузились. Переустановите Cool Clock или обновите WebView2 Runtime.");
            if(options.seconds&&elapsed>=options.seconds*1000ULL){if(std::any_of(views.begin(),views.end(),[](auto& view){return !view->ready;})){resultCode=1;errors.push_back(L"Smoke timeout before all views reported ready");}Stop();}
            return 0;
        }
    }
    return DefWindowProcW(hwnd,msg,wp,lp);
}
static bool MakeView(const RECT& rect,bool primary) {
    auto v=std::make_unique<View>();v->primary=primary;
    DWORD style=options.mode==Mode::Window?WS_OVERLAPPEDWINDOW:options.mode==Mode::Embedded?WS_CHILD:WS_POPUP;
    DWORD ex=options.mode==Mode::Screen?WS_EX_TOPMOST|WS_EX_TOOLWINDOW:0;
    HWND parent=options.mode==Mode::Embedded?reinterpret_cast<HWND>(options.parent):nullptr;
    HWND hwnd=CreateWindowExW(ex,L"CoolClock",L"Cool Clock",style,rect.left,rect.top,rect.right-rect.left,rect.bottom-rect.top,parent,nullptr,instance,v.get());
    if(!hwnd){Error(nullptr,L"Не удалось создать окно",HRESULT_FROM_WIN32(GetLastError()));return false;}
    views.push_back(std::move(v));ShowWindow(hwnd,SW_SHOW);WTSRegisterSessionNotification(hwnd,NOTIFY_FOR_THIS_SESSION);if(primary)SetTimer(hwnd,1,100,nullptr);return true;
}
static BOOL CALLBACK Monitor(HMONITOR,HDC,LPRECT rect,LPARAM) {return MakeView(*rect,views.empty())?TRUE:FALSE;}
static void Config() {
    HWND parent=reinterpret_cast<HWND>(options.parent);if(!IsWindow(parent))parent=nullptr;
    configWindow=CreateWindowExW(WS_EX_DLGMODALFRAME,L"CoolClock",L"Параметры Cool Clock",WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU,CW_USEDEFAULT,CW_USEDEFAULT,460,200,parent,nullptr,instance,nullptr);
    if(!configWindow){Error(nullptr,L"Не удалось открыть параметры");return;}
    soundCheck=CreateWindowW(L"BUTTON",L"Воспроизводить звук заставки",WS_VISIBLE|WS_CHILD|WS_TABSTOP|BS_AUTOCHECKBOX,24,25,400,28,configWindow,reinterpret_cast<HMENU>(100),instance,nullptr);
    SendMessageW(soundCheck,BM_SETCHECK,sound?BST_CHECKED:BST_UNCHECKED,0);
    CreateWindowW(L"STATIC",L"В миниатюре настроек звук всегда выключен.",WS_VISIBLE|WS_CHILD,24,62,400,24,configWindow,reinterpret_cast<HMENU>(101),instance,nullptr);
    CreateWindowW(L"BUTTON",L"Сохранить",WS_VISIBLE|WS_CHILD|WS_TABSTOP|BS_DEFPUSHBUTTON,210,105,100,30,configWindow,reinterpret_cast<HMENU>(IDOK),instance,nullptr);
    CreateWindowW(L"BUTTON",L"Отмена",WS_VISIBLE|WS_CHILD|WS_TABSTOP,320,105,100,30,configWindow,reinterpret_cast<HMENU>(IDCANCEL),instance,nullptr);
    UINT dpi=GetDpiForWindow(configWindow);
    if(!dpi)dpi=96;
    RECT bounds{0,0,MulDiv(448,dpi,96),MulDiv(154,dpi,96)};
    AdjustWindowRectExForDpi(&bounds,WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU,FALSE,WS_EX_DLGMODALFRAME,dpi);
    SetWindowPos(configWindow,nullptr,0,0,bounds.right-bounds.left,bounds.bottom-bounds.top,SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE);
    LayoutConfig(dpi);
    ShowWindow(configWindow,SW_SHOW);SetFocus(soundCheck);
}
static std::string JsonString(const std::wstring& value) {
    int n=WideCharToMultiByte(CP_UTF8,0,value.c_str(),static_cast<int>(value.size()),nullptr,0,nullptr,nullptr);
    std::string utf8(n,'\0');WideCharToMultiByte(CP_UTF8,0,value.c_str(),static_cast<int>(value.size()),utf8.data(),n,nullptr,nullptr);
    std::string out="\"";
    for(unsigned char c:utf8){if(c=='"'||c=='\\'){out+='\\';out+=c;}else if(c<32){char escaped[7];snprintf(escaped,sizeof(escaped),"\\u%04x",c);out+=escaped;}else out+=c;}
    return out+"\"";
}
static void Report() {
    if(options.report.empty())return;
    FILE* file=_wfopen(options.report.c_str(),L"wb");if(!file){resultCode=1;return;}
    size_t ready=0;for(auto& v:views)if(v->ready)++ready;
    // No URLs, user paths or audio data are included in the diagnostic report.
    fprintf(file,"{\"schema\":1,\"exitCode\":%d,\"views\":%zu,\"readyViews\":%zu,\"errorCount\":%zu,\"elapsedMs\":%llu,\"errors\":[",resultCode,views.size(),ready,errors.size(),static_cast<unsigned long long>(GetTickCount64()-started));
    for(size_t i=0;i<errors.size();++i)fprintf(file,"%s%s",i?",":"",JsonString(errors[i]).c_str());
    fputs("]}\n",file);fclose(file);
}
int WINAPI wWinMain(HINSTANCE h,HINSTANCE,PWSTR,int) {
    instance=h;started=GetTickCount64();
    int argc=0;LPWSTR* argv=CommandLineToArgvW(GetCommandLineW(),&argc);std::vector<std::wstring> args;
    if(!argv)return 2;for(int i=1;i<argc;++i)args.emplace_back(argv[i]);LocalFree(argv);
    if(!Parse(args,options)){MessageBoxW(nullptr,L"Неверные параметры. Используйте /s, /c, /p HWND или --preview.",L"Cool Clock",MB_OK|MB_ICONERROR);return 2;}
    if(options.mode==Mode::SelfTest){int result=SelfTest();return result?result:OptionsSelfTest();}
    if(options.mode==Mode::CloseExisting)return CloseExisting(options.closeTarget);
    if(options.mode==Mode::Embedded&&!IsWindow(reinterpret_cast<HWND>(options.parent)))return 2;
    wchar_t path[32768];DWORD length=GetModuleFileNameW(nullptr,path,32768);if(!length||length>=32768)return 2;
    exeDirectory=std::wstring(path,length);exeDirectory.resize(exeDirectory.find_last_of(L"\\/"));
    if(options.mode!=Mode::CheckRuntime&&options.mode!=Mode::Config){DWORD attrs=GetFileAttributesW((exeDirectory+L"\\web\\clock.html").c_str());if(attrs==INVALID_FILE_ATTRIBUTES||(attrs&FILE_ATTRIBUTE_DIRECTORY)){Error(nullptr,L"Файлы заставки отсутствуют. Переустановите Cool Clock.");Report();return 1;}}
    HRESULT com=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);if(FAILED(com))return 2;
    HMODULE loader=nullptr;
    using VersionFn=HRESULT(STDAPICALLTYPE*)(PCWSTR,LPWSTR*);
    using CreateFn=HRESULT(STDAPICALLTYPE*)(PCWSTR,PCWSTR,ICoreWebView2EnvironmentOptions*,ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler*);
    CreateFn create=nullptr;bool runtime=false;
    if(options.mode!=Mode::Config){
        loader=LoadLibraryExW((exeDirectory+L"\\WebView2Loader.dll").c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
        auto version=loader?reinterpret_cast<VersionFn>(GetProcAddress(loader,"GetAvailableCoreWebView2BrowserVersionString")):nullptr;
        create=loader?reinterpret_cast<CreateFn>(GetProcAddress(loader,"CreateCoreWebView2EnvironmentWithOptions")):nullptr;
        LPWSTR browserVersion=nullptr;runtime=(EvergreenInstalled(HKEY_LOCAL_MACHINE,KEY_WOW64_32KEY)||EvergreenInstalled(HKEY_CURRENT_USER,0))&&version&&create&&SUCCEEDED(version(nullptr,&browserVersion))&&browserVersion;CoTaskMemFree(browserVersion);
        if(options.mode==Mode::CheckRuntime){if(loader)FreeLibrary(loader);CoUninitialize();return runtime?0:1;}
        if(!runtime){Error(nullptr,L"Нужен Microsoft Edge WebView2 Runtime. Запустите установщик Cool Clock, чтобы установить его.");Report();if(loader)FreeLibrary(loader);CoUninitialize();return 1;}
    }
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    WNDCLASSW wc{};wc.hInstance=instance;wc.lpfnWndProc=Procedure;wc.lpszClassName=L"CoolClock";wc.hCursor=LoadCursorW(nullptr,IDC_ARROW);wc.hbrBackground=reinterpret_cast<HBRUSH>(COLOR_WINDOW+1);wc.hIcon=LoadIconW(instance,MAKEINTRESOURCEW(1));if(!wc.hIcon)wc.hIcon=LoadIconW(nullptr,IDI_APPLICATION);RegisterClassW(&wc);
    sound=ReadSound();
    if(options.mode==Mode::Config)Config();
    else {
        if(options.mode==Mode::Screen)EnumDisplayMonitors(nullptr,nullptr,Monitor,0);
        else if(options.mode==Mode::Embedded){RECT r;GetClientRect(reinterpret_cast<HWND>(options.parent),&r);MakeView(r,true);}
        else {RECT r{0,0,984,718};AdjustWindowRectEx(&r,WS_OVERLAPPEDWINDOW,FALSE,0);r.right-=r.left;r.bottom-=r.top;r.left=100;r.top=100;r.right+=100;r.bottom+=100;MakeView(r,true);}
        if(views.empty()&&!stopping)Error(nullptr,L"Не найден экран для заставки");
        if(!stopping){
            PWSTR appData=nullptr;HRESULT hr=SHGetKnownFolderPath(FOLDERID_LocalAppData,KF_FLAG_CREATE,nullptr,&appData);
            if(FAILED(hr))Error(nullptr,L"Не удалось открыть папку данных приложения",hr);
            else {
                std::wstring dataRoot=std::wstring(appData)+L"\\CoolClock";CoTaskMemFree(appData);
                CreateDirectoryW(dataRoot.c_str(),nullptr);
                std::wstring data=dataRoot+L"\\WebView2";
                auto callback=Handler<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler,HRESULT,ICoreWebView2Environment*>(IID_ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler,[](HRESULT hr,ICoreWebView2Environment* env)->HRESULT {if(stopping)return S_OK;if(FAILED(hr)||!env){Error(nullptr,L"Не удалось запустить WebView2",hr);return S_OK;}environment=env;env->AddRef();for(auto& v:views)Attach(v.get());return S_OK;});
                auto environmentOptions=new Options();hr=create(nullptr,data.c_str(),environmentOptions,callback);environmentOptions->Release();callback->Release();if(FAILED(hr))Error(nullptr,L"Не удалось инициализировать WebView2",hr);
            }
        }
    }
    MSG msg{};while(GetMessageW(&msg,nullptr,0,0)>0){if(configWindow&&IsDialogMessageW(configWindow,&msg))continue;TranslateMessage(&msg);DispatchMessageW(&msg);}
    Stop();Report();Release(environment);CoUninitialize();if(loader)FreeLibrary(loader);return resultCode;
}
#endif
