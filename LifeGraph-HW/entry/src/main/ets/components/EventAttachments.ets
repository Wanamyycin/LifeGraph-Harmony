import { fileUri } from '@kit.CoreFileKit';
import { MediaAsset, Palette } from '../domain/Models';
import { VoicePlayer } from './VoicePlayer';

@Component
export struct EventAttachments {
  @Prop assets: MediaAsset[] = [];
  @Prop mediaRoot: string = '';
  @Prop editable: boolean = false;
  @Prop disabled: boolean = false;
  @Prop palette: Palette = new Palette();
  onImage: (uri: string) => void = () => {};
  onCover: (id: string) => void = () => {};
  onRemove: (id: string) => void = () => {};

  private path(asset: MediaAsset): string {
    return this.mediaRoot.length > 0 && /^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(asset.storagePath) && !asset.storagePath.includes('..') ?
      this.mediaRoot + '/' + asset.storagePath : '';
  }

  build() {
    Column({ space: 12 }) {
      ForEach(this.assets, (asset: MediaAsset) => {
        Column({ space: 8 }) {
          if (asset.mediaKind === 'image' && this.path(asset).length > 0) {
            Image(fileUri.getUriFromPath(this.path(asset))).width('100%').height(170).objectFit(ImageFit.Cover).borderRadius(14)
              .id('attachment-image-' + asset.id).onClick(() => this.onImage(fileUri.getUriFromPath(this.path(asset))))
          } else if (asset.mediaKind === 'audio' && this.path(asset).length > 0) {
            VoicePlayer({ filePath: this.path(asset), palette: this.palette })
          }
          if (this.editable) {
            Row({ space: 10 }) {
              if (asset.mediaKind === 'image') {
                Button(asset.role === 'cover' ? '✓ 事件封面' : '设为封面').fontSize(12).fontColor(this.palette.primary).backgroundColor(this.palette.soft)
                  .id('attachment-cover-' + asset.id).onClick(() => this.onCover(asset.id))
              }
              Button('移除附件').fontSize(12).fontColor(this.palette.danger).backgroundColor(Color.Transparent)
                .id('attachment-remove-' + asset.id).onClick(() => this.onRemove(asset.id))
            }.enabled(!this.disabled)
          }
        }.width('100%')
      }, (asset: MediaAsset) => asset.id + ':' + asset.role)
    }.width('100%')
  }
}
