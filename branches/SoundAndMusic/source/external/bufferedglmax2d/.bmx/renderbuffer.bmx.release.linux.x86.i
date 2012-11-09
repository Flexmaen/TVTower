import brl.blitz
import brl.graphics
import pub.glew
import brl.glmax2d
TRenderState^Object{
.texture_name%&
.render_mode%&
.blend_source%&
.blend_dest%&
.alpha_func%&
.alpha_ref#&
.sc_enabled%&
.sc_x%&
.sc_y%&
.sc_w%&
.sc_h%&
.line_width#&
-New%()="_bb_TRenderState_New"
-Delete%()="_bb_TRenderState_Delete"
-Bind%()F="_bb_TRenderState_Bind"
-Restore%()F="_bb_TRenderState_Restore"
-Clone:TRenderState()F="_bb_TRenderState_Clone"
+SetTexture%(tex%)="_bb_TRenderState_SetTexture"
+RestoreState%(state:TRenderState="bbNullObject")="_bb_TRenderState_RestoreState"
}F="bb_TRenderState"
TRenderBuffer^Object{
._vertices@*&
._texcoords@*&
._colors@*&
._vertices_len%&
._texcoords_len%&
._colors_len%&
._index%&
._sets%&
._indices@*&
._counts@*&
._indices_length%&
._lock%&
._render_indices@*&
._render_states@*&
._state_capacity%&
._states_top%&
-New%()="_bb_TRenderBuffer_New"
-Delete%()="_bb_TRenderBuffer_Delete"
-SetTexture%(name%)F="_bb_TRenderBuffer_SetTexture"
-SetMode%(mode%)F="_bb_TRenderBuffer_SetMode"
-SetBlendFunc%(source%,dest%)F="_bb_TRenderBuffer_SetBlendFunc"
-SetAlphaFunc%(func%,ref#)F="_bb_TRenderBuffer_SetAlphaFunc"
-SetScissorTest%(enabled%,x%,y%,w%,h%)F="_bb_TRenderBuffer_SetScissorTest"
-SetLineWidth%(width#)F="_bb_TRenderBuffer_SetLineWidth"
-AddVerticesEx%(elements%,vertices@*,texcoords@*,colors@*)F="_bb_TRenderBuffer_AddVerticesEx"
-LockBuffers%()F="_bb_TRenderBuffer_LockBuffers"
-UnlockBuffers%()F="_bb_TRenderBuffer_UnlockBuffers"
-Render%()F="_bb_TRenderBuffer_Render"
-Reset%()F="_bb_TRenderBuffer_Reset"
}F="bb_TRenderBuffer"
