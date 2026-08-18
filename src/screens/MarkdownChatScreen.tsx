import React, {useCallback, useRef, useState} from 'react';
import {
  ActivityIndicator,
  Linking,
  Platform,
  Pressable,
  StatusBar,
  StyleSheet,
  Text,
  View,
  useColorScheme,
} from 'react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {
  MarkdownChatList,
  type MdListHandle,
  type MdMessage,
} from '../../modules/react-native-md-list/src';
import {buildTranscript, STREAMING_ANSWER} from '../data/dummyMessages';

const PAGE_PAIRS = 4;
const FIRST_OFFSET = 100;
const MAX_PAGES = 6;

export default function MarkdownChatScreen() {
  const insets = useSafeAreaInsets();
  const systemScheme = useColorScheme();

  const [scheme, setScheme] = useState<'light' | 'dark'>(
    systemScheme === 'dark' ? 'dark' : 'light',
  );
  const [messages, setMessages] = useState<MdMessage[]>(() =>
    buildTranscript(PAGE_PAIRS, FIRST_OFFSET),
  );
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [atBottom, setAtBottom] = useState(true);
  const [toast, setToast] = useState<string | null>(null);
  const [streaming, setStreaming] = useState(false);

  const listRef = useRef<MdListHandle>(null);
  const oldestOffset = useRef(FIRST_OFFSET);
  const pagesLoaded = useRef(0);
  const streamTimer = useRef<ReturnType<typeof setInterval> | null>(null);

  const flashToast = useCallback((text: string) => {
    setToast(text);
    setTimeout(() => setToast(null), 1400);
  }, []);

  // ---- lazy load older history -------------------------------------------
  const handleStartReached = useCallback(() => {
    if (loadingOlder || pagesLoaded.current >= MAX_PAGES) {
      return;
    }
    setLoadingOlder(true);
    // stand-in for a paginated API call
    setTimeout(() => {
      oldestOffset.current -= PAGE_PAIRS;
      pagesLoaded.current += 1;
      const older = buildTranscript(PAGE_PAIRS, oldestOffset.current);
      setMessages(prev => [...older, ...prev]);
      setLoadingOlder(false);
    }, 450);
  }, [loadingOlder]);

  // ---- streaming demo -----------------------------------------------------
  const startStreaming = useCallback(() => {
    if (streamTimer.current) {
      return;
    }
    const id = `stream-${Date.now()}`;
    setMessages(prev => [
      ...prev,
      {id: `${id}-q`, role: 'user', markdown: 'Giải thích cách màn này chạy mượt đi'},
      {id, role: 'assistant', markdown: '', streaming: true},
    ]);
    setStreaming(true);

    let cursor = 0;
    streamTimer.current = setInterval(() => {
      // ~6 chars per tick at 60fps mimics a real token stream
      cursor = Math.min(STREAMING_ANSWER.length, cursor + 6);
      const chunk = STREAMING_ANSWER.slice(0, cursor);
      const done = cursor >= STREAMING_ANSWER.length;
      setMessages(prev =>
        prev.map(m => (m.id === id ? {...m, markdown: chunk, streaming: !done} : m)),
      );
      if (done && streamTimer.current) {
        clearInterval(streamTimer.current);
        streamTimer.current = null;
        setStreaming(false);
      }
    }, 16);
  }, []);

  const isDark = scheme === 'dark';
  const palette = isDark ? darkPalette : lightPalette;

  return (
    <View style={[styles.root, {backgroundColor: palette.bg}]}>
      <StatusBar barStyle={isDark ? 'light-content' : 'dark-content'} />

      <MarkdownChatList
        ref={listRef}
        style={styles.list}
        messages={messages}
        colorScheme={scheme}
        fontSize={16}
        topInset={insets.top + 52}
        bottomInset={insets.bottom + 64}
        loadingOlder={loadingOlder}
        prefetchRows={14}
        onStartReached={handleStartReached}
        onAtBottomChange={setAtBottom}
        onLinkPress={url => {
          Linking.openURL(url).catch(() => flashToast('Không mở được liên kết'));
        }}
        onCodeCopy={(_code, language) => flashToast(`Đã copy code ${language}`)}
      />

      {/* header */}
      <View
        style={[
          styles.header,
          {paddingTop: insets.top + 8, backgroundColor: palette.chrome, borderBottomColor: palette.border},
        ]}>
        <Text style={[styles.title, {color: palette.text}]} numberOfLines={1}>
          Markdown Chat · {Platform.OS === 'ios' ? 'UITableView' : 'RecyclerView'}
        </Text>
        <Pressable
          hitSlop={10}
          onPress={() => setScheme(prev => (prev === 'dark' ? 'light' : 'dark'))}>
          <Text style={[styles.headerAction, {color: palette.accent}]}>
            {isDark ? 'Light' : 'Dark'}
          </Text>
        </Pressable>
      </View>

      {loadingOlder && (
        <View style={[styles.loaderRow, {top: insets.top + 60}]}>
          <ActivityIndicator size="small" color={palette.subtle} />
          <Text style={[styles.loaderText, {color: palette.subtle}]}>Đang tải tin cũ hơn…</Text>
        </View>
      )}

      {!atBottom && (
        <Pressable
          style={[styles.jumpButton, {bottom: insets.bottom + 76, backgroundColor: palette.chrome, borderColor: palette.border}]}
          onPress={() => listRef.current?.scrollToBottom(true)}>
          <Text style={{color: palette.text}}>↓ Mới nhất</Text>
        </Pressable>
      )}

      {toast && (
        <View style={[styles.toast, {bottom: insets.bottom + 128}]}>
          <Text style={styles.toastText}>{toast}</Text>
        </View>
      )}

      {/* footer */}
      <View
        style={[
          styles.footer,
          {paddingBottom: insets.bottom + 10, backgroundColor: palette.chrome, borderTopColor: palette.border},
        ]}>
        <Pressable
          style={[styles.cta, {backgroundColor: streaming ? palette.border : palette.accent}]}
          disabled={streaming}
          onPress={startStreaming}>
          <Text style={styles.ctaText}>
            {streaming ? 'Đang stream…' : 'Mô phỏng câu trả lời streaming'}
          </Text>
        </Pressable>
        <Text style={[styles.counter, {color: palette.subtle}]}>{messages.length} tin</Text>
      </View>
    </View>
  );
}

const lightPalette = {
  bg: '#FFFFFF',
  chrome: 'rgba(255,255,255,0.94)',
  border: '#E5E5E5',
  text: '#0D0D0D',
  subtle: '#6E6E80',
  accent: '#1A73E8',
};

const darkPalette = {
  bg: '#212121',
  chrome: 'rgba(33,33,33,0.94)',
  border: '#333333',
  text: '#ECECEC',
  subtle: '#9B9B9B',
  accent: '#7AB7FF',
};

const styles = StyleSheet.create({
  root: {flex: 1},
  list: {flex: 1},
  header: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    paddingHorizontal: 16,
    paddingBottom: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  title: {fontSize: 16, fontWeight: '600', flexShrink: 1},
  headerAction: {fontSize: 15, fontWeight: '600'},
  loaderRow: {
    position: 'absolute',
    alignSelf: 'center',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  loaderText: {fontSize: 13},
  jumpButton: {
    position: 'absolute',
    alignSelf: 'center',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 18,
    borderWidth: StyleSheet.hairlineWidth,
  },
  toast: {
    position: 'absolute',
    alignSelf: 'center',
    backgroundColor: 'rgba(0,0,0,0.82)',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 16,
  },
  toastText: {color: '#FFFFFF', fontSize: 13},
  footer: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    paddingHorizontal: 16,
    paddingTop: 10,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  cta: {flex: 1, paddingVertical: 12, borderRadius: 22, alignItems: 'center'},
  ctaText: {color: '#FFFFFF', fontWeight: '600'},
  counter: {fontSize: 12},
});
