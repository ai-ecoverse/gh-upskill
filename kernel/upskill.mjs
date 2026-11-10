export default async function upskill(ctx) {
  const exe = await ctx.fs.readlink('/proc/self/exe');
  const kernel = exe.slice(0, exe.lastIndexOf('/'));
  const script = `${kernel.slice(0, kernel.lastIndexOf('/'))}/upskill`;
  const child = await ctx.spawn({ argv: ['/bin/bash', script, ...ctx.argv.slice(1)] });
  const { status } = await child.wait();
  return status;
}
