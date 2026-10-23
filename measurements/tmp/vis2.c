__attribute__((visibility("default"), used)) int vis_used(int x){return x+1;}
__attribute__((visibility("default"))) int vis_plain(int x){return x+1;}
int main(void){return 0;}
