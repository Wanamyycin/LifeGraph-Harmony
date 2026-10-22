import { NativeApp } from '../components/NativeApp';
import { PeoplePageController } from '../components/PeoplePageController';

@Entry
@Component
struct Index {
  private pageController: PeoplePageController = new PeoplePageController();

  onBackPress(): boolean {
    return this.pageController.onBackPress();
  }

  build() {
    Column() {
      NativeApp({ controller: this.pageController })
    }.width('100%').height('100%')
  }
}
