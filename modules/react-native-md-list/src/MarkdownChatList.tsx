import React, {forwardRef, useCallback, useImperativeHandle, useMemo, useRef} from 'react';
import {StyleSheet, View, useColorScheme, type StyleProp, type ViewStyle} from 'react-native';
import MdListNativeView, {Commands} from './MdListViewNativeComponent';
import type {MdListHandle, MdMessage} from './types';

export type MarkdownChatListProps = {
  messages: MdMessage[];
  style?: StyleProp<ViewStyle>;
  colorScheme?: 'light' | 'dark';
  fontSize?: number;
  topInset?: number;
  bottomInset?: number;
  loadingOlder?: boolean;
  autoScrollToBottom?: boolean;
  /** rows laid out ahead of the viewport on a background thread */
  prefetchRows?: number;
  onStartReached?: (oldestId: string) => void;
  onLinkPress?: (url: string) => void;
  onCodeCopy?: (code: string, language: string) => void;
  onAtBottomChange?: (atBottom: boolean) => void;
};

/**
 * Thin JS shell. The list, the markdown parser, the text layout and the cell
 * recycling are all native (RecyclerView on Android, UITableView on iOS), so JS
 * never touches per-row work and the shadow tree stays 1 node deep.
 */
export const MarkdownChatList = forwardRef<MdListHandle, MarkdownChatListProps>(
  function MarkdownChatListInner(props, ref) {
    const {
      messages,
      style,
      colorScheme,
      fontSize = 16,
      topInset = 0,
      bottomInset = 0,
      loadingOlder = false,
      autoScrollToBottom = true,
      prefetchRows = 12,
      onStartReached,
      onLinkPress,
      onCodeCopy,
      onAtBottomChange,
    } = props;

    const nativeRef = useRef<React.ComponentRef<typeof MdListNativeView>>(null);
    const systemScheme = useColorScheme();
    const scheme = colorScheme ?? (systemScheme === 'dark' ? 'dark' : 'light');

    useImperativeHandle(
      ref,
      () => ({
        scrollToBottom: (animated = true) => {
          if (nativeRef.current) {
            Commands.scrollToBottom(nativeRef.current, animated);
          }
        },
        scrollToMessage: (messageId: string, animated = true) => {
          if (nativeRef.current) {
            Commands.scrollToMessage(nativeRef.current, messageId, animated);
          }
        },
      }),
      [],
    );

    // Keep the prop identity stable-ish: only the fields the native side reads.
    const nativeMessages = useMemo(
      () =>
        messages.map(m => ({
          id: m.id,
          role: m.role,
          markdown: m.markdown,
          streaming: m.streaming === true,
        })),
      [messages],
    );

    const handleStartReached = useCallback(
      (e: {nativeEvent: {oldestId: string}}) => onStartReached?.(e.nativeEvent.oldestId),
      [onStartReached],
    );
    const handleLinkPress = useCallback(
      (e: {nativeEvent: {url: string}}) => onLinkPress?.(e.nativeEvent.url),
      [onLinkPress],
    );
    const handleCodeCopy = useCallback(
      (e: {nativeEvent: {code: string; language: string}}) =>
        onCodeCopy?.(e.nativeEvent.code, e.nativeEvent.language),
      [onCodeCopy],
    );
    const handleAtBottom = useCallback(
      (e: {nativeEvent: {atBottom: boolean}}) => onAtBottomChange?.(e.nativeEvent.atBottom),
      [onAtBottomChange],
    );

    return (
      <View style={[styles.fill, style]} collapsable={false}>
        <MdListNativeView
          ref={nativeRef}
          style={styles.fill}
          messages={nativeMessages}
          colorScheme={scheme}
          fontSize={fontSize}
          topInset={topInset}
          bottomInset={bottomInset}
          loadingOlder={loadingOlder}
          autoScrollToBottom={autoScrollToBottom}
          prefetchRows={prefetchRows}
          onStartReached={onStartReached ? handleStartReached : undefined}
          onLinkPress={onLinkPress ? handleLinkPress : undefined}
          onCodeCopy={onCodeCopy ? handleCodeCopy : undefined}
          onAtBottomChange={onAtBottomChange ? handleAtBottom : undefined}
        />
      </View>
    );
  },
);

MarkdownChatList.displayName = 'MarkdownChatList';

const styles = StyleSheet.create({fill: {flex: 1}});
