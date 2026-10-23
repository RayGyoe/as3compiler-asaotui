__attribute__((visibility("default"))) int vis_default(int x){return x+1;}
static int vis_static(int x){return x+2;}
int main(void){return vis_static(0);}
